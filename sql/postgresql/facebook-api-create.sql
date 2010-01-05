create table fb_users (
    uid bigint not null primary key,
    last_friends_update timestamptz,
    auth_token text,
    session_key text,
    session_expires text
);

create table fb_friends (
    uid bigint,
    friend_uid bigint
);

create table fb_groups (
    gid bigint,
    uid bigint
);

create table oacs_fb_user_map (
    user_id bigint not null primary key,
    uid bigint
);