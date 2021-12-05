------------------
-- CONNECTIVITY --
------------------

CREATE OR REPLACE FUNCTION check_connection() returns boolean as $$
BEGIN
RETURN TRUE;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;

----------
-- AUTH --
----------

CREATE OR REPLACE FUNCTION delete_user() returns void AS $$
BEGIN
delete from auth.users where id = auth.uid();
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;

----------------------
-- PROFILE UPDATING --
----------------------

CREATE OR REPLACE FUNCTION profile_update(
  new_bio varchar, new_color smallint, new_icon smallint, new_name varchar, new_status varchar
) returns void AS $$
BEGIN
update public.profiles
set
  name = new_name,
  status = new_status,
  bio = new_bio,
  color = new_color,
  icon = new_icon
where (id = auth.uid());
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;



---------------------
-- PROFILE QUERIES --
---------------------

create or replace function profile_from_email(_email varchar) returns setof profiles as $func$
select profiles.* from auth.users
left join profiles on users.id = profiles.id
where users.email = _email;
$func$ LANGUAGE sql
SECURITY DEFINER;


-- sorts out profiles with relation to auth.uid()
create or replace function query_profiles()
returns setof public.profiles as $func$
  SELECT profiles.*
  FROM public.profiles
  left join relations on relations.id = auth.uid() and relations.other_id = profiles.id
  where relations.id is null and profiles.id <> auth.uid();
$func$
LANGUAGE sql;

create or replace function query_profiles_popularity()
returns setof public.profiles as $func$
  SELECT *
  FROM query_profiles()
  order by points;
$func$
LANGUAGE sql;

create or replace function query_profiles_name(_name varchar(8))
returns setof public.profiles as $func$
  SELECT *
  FROM query_profiles() as profiles
  order by levenshtein(_name, profiles.name) + levenshtein(substring(_name, 0, 1), substring(profiles.name, 0, 1)) * 2;
$func$
LANGUAGE sql;

create or replace function query_profiles_name_popularity(_name varchar(8))
returns setof public.profiles as $func$
  SELECT *
  FROM query_profiles() as profiles
  order by levenshtein(_name, profiles.name) / 10, profiles.points;
$func$
LANGUAGE sql;

----------
-- CHAT --
----------
CREATE OR REPLACE FUNCTION send_message(chat_id uuid, other_id uuid, content text)
returns void as
$$
BEGIN
insert into messages(chat_id, sender, receiver, content)
values (chat_id, auth.uid(), other_id, content);
END;
$$
language plpgsql
SECURITY DEFINER;

---------------
-- RELATIONS --
---------------
CREATE OR REPLACE FUNCTION get_relations() returns
table (
  id uuid,
  name varchar,
  status varchar,
  bio varchar,
  color int,
  icon int,
  points int,
  gives int,
  chat_id uuid,
  state relationship_state
)
AS $$
  SELECT profiles.*, relations.id as chat_id, relations.state
  FROM relations
  left join profiles on relations.other_id = profiles.id
  where relations.id = auth.uid()
$$
LANGUAGE sql;

CREATE OR REPLACE FUNCTION insert_relation(
  id uuid,
  other_id uuid,
  state relationship_state,
  other_state relationship_state
) returns void as $$
declare
chat_id uuid;
begin
select uuid_generate_v4() into chat_id;

insert into chats values (chat_id);

insert into relations values
(id, other_id, chat_id, state),
(other_id, id, chat_id, other_state);
end;
$$
language plpgsql;


CREATE OR REPLACE FUNCTION relations_accept(_id uuid) returns void AS $$
DECLARE
relations_between_found INT;
BEGIN

SELECT count(*)
into relations_between_found
from relations
where relations.id = auth.uid() and other_id = _id and state = 'request_pending';

if relations_between_found <> 1 then
  RAISE EXCEPTION 'no_request_between_found';
end if;

update relations set
state = 'friends'
where
(id = auth.uid() and other_id = _id) or
(id = _id and other_id = auth.uid());
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


CREATE OR REPLACE FUNCTION relations_block(_id uuid) returns void AS $$
DECLARE
blocked_relations_by_id_found INT;
relations_by_id_found INT;
BEGIN

SELECT count(*)
into blocked_relations_by_id_found
from relations
where relations.other_id = auth.uid() and relations.id = _id and state = 'blocked';

SELECT count(*)
into relations_by_id_found
from relations
where relations.other_id = auth.uid() and relations.id = _id;

if blocked_relations_by_id_found = 1 then
  update relations
  set state = 'blocked'
  where id = auth.uid() and other_id = _id;
else
  if(relations_by_id_found > 0) then
    update relations
    set state = 'blocked'
    where id = auth.uid() and other_id = _id;

    update relations
    set state = 'blocked_by'
    where id = _id and other_id = auth.uid();
  else
    perform insert_relation(auth.uid(), _id, 'blocked', 'blocked_by');
  end if;
end if;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


CREATE OR REPLACE FUNCTION relations_reject(_id uuid) returns void AS $$
DECLARE
relations_between_found INT;
BEGIN

SELECT count(*)
into relations_between_found
from relations
where relations.id = auth.uid() and other_id = _id and state = 'request_pending';

if relations_between_found <> 1 then
  RAISE EXCEPTION 'no_request_between_found';
end if;

delete from relations
where
(id = auth.uid() and other_id = _id) or
(id = _id and other_id = auth.uid());
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


CREATE OR REPLACE FUNCTION relations_request(_id uuid) returns void AS $$
DECLARE
relations_between_found INT;
BEGIN

SELECT count(*)
into relations_between_found
from relations
where relations.id = auth.uid() and other_id = _id;

if relations_between_found = 1 then
  RAISE EXCEPTION 'relation_already_exists';
end if;

perform insert_relation(auth.uid(), _id, 'requesting', 'request_pending');
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


CREATE OR REPLACE FUNCTION relations_take_back_request(_id uuid) returns void AS $$
DECLARE
relations_between_found INT;
BEGIN

SELECT count(*)
into relations_between_found
from relations
where relations.id = auth.uid() and other_id = _id and state = 'requesting';

if relations_between_found <> 1 then
  RAISE EXCEPTION 'no_request_between_found';
end if;

delete from relations
where
(id = auth.uid() and other_id = _id) or
(id = _id and other_id = auth.uid());
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


CREATE OR REPLACE FUNCTION relations_unblock(_id uuid) returns void AS $$
DECLARE
  blocked_relations_found INT;
  blocked_by_relations_found INT;
BEGIN
  select COUNT(*)
  into blocked_relations_found
  from relations
  where
    id = auth.uid()
    and other_id = _id
    and state = 'blocked';

  select COUNT(*)
  into blocked_by_relations_found
  from relations
  where
    id = _id
    and other_id = auth.uid()
    and state = 'blocked';

  if blocked_relations_found = 0 then
    raise exception 'no_blocked_relations_found';
  end if;

  if blocked_by_relations_found = 1 then
    update relations
    set state = 'blocked_by'
    where id = auth.uid() and other_id = _id;
  else
    delete from relations
    where
      (id = auth.uid() and other_id = _id) or
      (id = _id and other_id = auth.uid());
  end if;

END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;


CREATE OR REPLACE FUNCTION relations_unfriend(_id uuid) returns void AS $$
DECLARE
relations_between_found INT;
BEGIN

SELECT count(*)
into relations_between_found
from relations
where relations.id = auth.uid() and other_id = _id and state = 'friends';

if relations_between_found <> 1 then
  RAISE EXCEPTION 'not_friends';
end if;

delete from relations
  where (id = _id and other_id = auth.uid()) or
    (id = auth.uid() and other_id = _id);
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER;
