DROP TABLE IF EXISTS commit;
DROP TABLE IF EXISTS language;
DROP TABLE IF EXISTS license;
DROP TABLE IF EXISTS repository_languages;
DROP TABLE IF EXISTS repository_license;
DROP TABLE IF EXISTS repository_topics;
DROP TABLE IF EXISTS repository;
DROP TABLE IF EXISTS star;
DROP TABLE IF EXISTS ticket;
DROP TABLE IF EXISTS topic;
DROP TABLE IF EXISTS users;

CREATE TABLE commit (
    repository_id integer,
    hash VARCHAR,
    created_by varchar,
    message varchar,
    created_at timestamp,
    PRIMARY KEY (repository_id, hash)
);

CREATE TABLE language (
    id serial PRIMARY KEY,
    name varchar
);

CREATE TABLE license (
    id serial PRIMARY KEY,
    name varchar,
    description varchar
);

CREATE TABLE repository (
    id serial PRIMARY KEY,
    name varchar,
    owner varchar,
    is_archived boolean,
    disk_usage_kb bigint,
    description varchar,
    created_at timestamp,
    pushed_at timestamp,
    code_of_conduct varchar
);

CREATE TABLE repository_languages (
    repository_id integer,
    language_id integer,
    size bigint,
    is_primary boolean,
    PRIMARY KEY (repository_id, language_id)
);

CREATE TABLE repository_license (
    repository_id integer,
    license_id integer,
    PRIMARY KEY (repository_id, license_id)
);

CREATE TABLE repository_topics (
    repository_id integer,
    topic_id integer,
    PRIMARY KEY (repository_id, topic_id)
);

CREATE TABLE star (
    repository_id integer,
    username varchar,
    starred_at timestamp,
    PRIMARY KEY (repository_id, username)
);

CREATE TABLE ticket (
    repository_id integer,
    ticket_id integer,
    created_by varchar,
    type varchar,
    status varchar,
    opened_at timestamp,
    closed_at timestamp,
    title varchar,
    data varchar,
    PRIMARY KEY (repository_id, ticket_id)
);

CREATE TABLE topic (
    id serial PRIMARY KEY,
    name varchar
);

CREATE TABLE users (
    username varchar PRIMARY KEY,
    email varchar,
    created_at timestamp,
    bio varchar
);
