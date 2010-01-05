alter table fb_friends alter column uid type bigint;
alter table fb_friends alter column friend_uid type bigint;

alter table fb_groups alter column gid type bigint;
alter table fb_groups alter column uid type bigint;

alter table fb_users alter column uid type bigint;

alter table oacs_fb_user_map alter column user_id type bigint;
alter table oacs_fb_user_map alter column uid type bigint;
