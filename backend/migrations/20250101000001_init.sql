-- ============================================================================
-- ChurchMS initial schema
-- Tenants, users, members, families, roles, sessions, audit log
-- ============================================================================

-- ---------------------------------------------------------------------------
-- churches: the tenant root. Every other table references this.
-- ---------------------------------------------------------------------------
CREATE TABLE churches (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    slug        TEXT NOT NULL UNIQUE,
    timezone    TEXT NOT NULL DEFAULT 'UTC',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX idx_churches_slug ON churches(slug) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- users: login accounts. Separate from members.
-- A user may or may not correspond to a member.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id          UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
    email              CITEXT NOT NULL,
    password_hash      TEXT NOT NULL,
    status             TEXT NOT NULL DEFAULT 'active'
                       CHECK (status IN ('active', 'suspended', 'deleted')),
    email_verified_at  TIMESTAMPTZ,
    last_login_at      TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ
);

-- Email must be unique within a church, but the same person could exist
-- in multiple churches (different tenants) with the same email.
CREATE UNIQUE INDEX uniq_users_church_email
    ON users(church_id, email)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_users_church ON users(church_id) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- families: households. Members belong to at most one family.
-- ---------------------------------------------------------------------------
CREATE TABLE families (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id         UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    address_line1     TEXT,
    address_line2     TEXT,
    city              TEXT,
    state             TEXT,
    postal_code       TEXT,
    country           TEXT,
    home_phone        TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ
);

CREATE INDEX idx_families_church ON families(church_id) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- members: people in the church. May link to a user account (nullable).
-- ---------------------------------------------------------------------------
CREATE TABLE members (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id          UUID NOT NULL REFERENCES churches(id) ON DELETE CASCADE,
    user_id            UUID REFERENCES users(id) ON DELETE SET NULL,
    family_id          UUID REFERENCES families(id) ON DELETE SET NULL,

    -- Identity
    first_name         TEXT NOT NULL,
    middle_name        TEXT,
    last_name          TEXT NOT NULL,
    preferred_name     TEXT,
    gender             TEXT CHECK (gender IN ('male', 'female', 'other', 'prefer_not_to_say')),
    date_of_birth      DATE,
    marital_status     TEXT CHECK (marital_status IN ('single', 'married', 'widowed', 'divorced', 'unknown')),

    -- Contact
    email              CITEXT,
    phone              TEXT,

    -- Media
    photo_url          TEXT,

    -- Church-specific
    membership_status  TEXT NOT NULL DEFAULT 'visitor'
                       CHECK (membership_status IN ('visitor', 'member', 'leader', 'inactive', 'transferred')),
    joined_at          DATE,
    notes              TEXT,

    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at         TIMESTAMPTZ
);

CREATE INDEX idx_members_church        ON members(church_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_members_family        ON members(family_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_members_user          ON members(user_id) WHERE user_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_members_last_first    ON members(church_id, last_name, first_name) WHERE deleted_at IS NULL;
CREATE INDEX idx_members_email         ON members(church_id, email) WHERE email IS NOT NULL AND deleted_at IS NULL;

-- One user account can be linked to at most one member per church.
CREATE UNIQUE INDEX uniq_members_user_church
    ON members(church_id, user_id)
    WHERE user_id IS NOT NULL AND deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- roles: named permission bundles. System roles have church_id = NULL.
-- ---------------------------------------------------------------------------
CREATE TABLE roles (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    church_id    UUID REFERENCES churches(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    description  TEXT,
    is_system    BOOLEAN NOT NULL DEFAULT false,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Name unique per tenant (NULL church_id = system role, unique globally).
CREATE UNIQUE INDEX uniq_roles_church_name
    ON roles(COALESCE(church_id, '00000000-0000-0000-0000-000000000000'::uuid), name);

-- ---------------------------------------------------------------------------
-- user_roles: many-to-many between users and roles.
-- ---------------------------------------------------------------------------
CREATE TABLE user_roles (
    user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id      UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    granted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX idx_user_roles_user ON user_roles(user_id);

-- ---------------------------------------------------------------------------
-- sessions: refresh tokens. Access tokens are stateless JWTs.
-- ---------------------------------------------------------------------------
CREATE TABLE sessions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash    TEXT NOT NULL UNIQUE,
    user_agent    TEXT,
    ip_address    INET,
    expires_at    TIMESTAMPTZ NOT NULL,
    revoked_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sessions_user    ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at) WHERE revoked_at IS NULL;

-- ---------------------------------------------------------------------------
-- audit_log: who did what, when. Append-only.
-- ---------------------------------------------------------------------------
CREATE TABLE audit_log (
    id             BIGSERIAL PRIMARY KEY,
    church_id      UUID REFERENCES churches(id) ON DELETE SET NULL,
    actor_user_id  UUID REFERENCES users(id) ON DELETE SET NULL,
    action         TEXT NOT NULL,
    entity_type    TEXT,
    entity_id      UUID,
    changes        JSONB,
    ip_address     INET,
    user_agent     TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_church_time ON audit_log(church_id, created_at DESC);
CREATE INDEX idx_audit_actor       ON audit_log(actor_user_id, created_at DESC);
CREATE INDEX idx_audit_entity      ON audit_log(entity_type, entity_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- updated_at trigger: auto-bump on UPDATE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_churches_updated_at  BEFORE UPDATE ON churches  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_users_updated_at     BEFORE UPDATE ON users     FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_members_updated_at   BEFORE UPDATE ON members   FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_families_updated_at  BEFORE UPDATE ON families  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_roles_updated_at     BEFORE UPDATE ON roles     FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Seed: default church + system roles.
-- The DEFAULT_CHURCH_ID in .env matches this.
-- ---------------------------------------------------------------------------
INSERT INTO churches (id, name, slug)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Church', 'default');

INSERT INTO roles (church_id, name, description, is_system) VALUES
    (NULL, 'admin',   'Full access to the church tenant',        true),
    (NULL, 'pastor',  'Pastoral care, sees all members and notes', true),
    (NULL, 'leader',  'Leads a ministry or group',                true),
    (NULL, 'member',  'Regular member self-service',              true);
