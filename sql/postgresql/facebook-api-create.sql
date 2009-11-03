create table fb_users (
    uid integer not null primary key,
    last_friends_update timestamptz,
    auth_token text,
    session_key text,
    session_expires text
);

create table fb_friends (
    uid integer,
    friend_uid integer
);

create table fb_groups (
    gid integer,
    uid integer
);

create table oacs_fb_user_map (
    user_id integer not null primary key,
    uid integer
);