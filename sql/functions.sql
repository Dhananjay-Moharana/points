CREATE OR REPLACE FUNCTION delete_user() returns void AS $$
  delete from auth.users where
$$ LANGUAGE plpgsql
SECURITY DEFINER;


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
    insert into relations(id, other_id, state) values
    (auth.uid(), _id, 'blocked'),
    (_id, auth.uid(), 'blocked_by');
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

insert into relations(id, other_id, state) VALUES
(auth.uid(), _id, 'requesting'),
(_id, auth.uid(), 'request_pending');
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
