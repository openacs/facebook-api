create table fb_users (
       uid integer,
       last_friends_update timestamptz
);

create table fb_friends (
       uid integer,
       friend_uid integer
);

create table fb_groups (
       gid integer,
       uid integer
);
