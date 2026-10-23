-- Souzou Supabase setup. Run this entire file in Supabase Dashboard > SQL Editor.
-- Public game files are isolated on Supabase Storage's origin; the site iframe uses sandbox="allow-scripts" only.
create extension if not exists pgcrypto;

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 70),
  description text not null check (char_length(description) between 1 and 600),
  category text not null default 'その他' check (category in ('アクション','パズル','アドベンチャー','アーケード','シミュレーション','その他')),
  game_url text not null,
  cover_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists games_created_at_idx on public.games(created_at desc);
create index if not exists games_category_idx on public.games(category);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(game_id,user_id)
);
create index if not exists reviews_game_id_idx on public.reviews(game_id);

create table if not exists public.game_likes (
  game_id uuid not null references public.games(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(game_id,user_id)
);

alter table public.games enable row level security;
alter table public.reviews enable row level security;
alter table public.game_likes enable row level security;

drop policy if exists "Anyone can read published games" on public.games;
create policy "Anyone can read published games" on public.games for select using (true);
drop policy if exists "Authenticated users can publish games" on public.games;
create policy "Authenticated users can publish games" on public.games for insert to authenticated with check (auth.uid() = owner_id);
drop policy if exists "Owners can update their games" on public.games;
create policy "Owners can update their games" on public.games for update to authenticated using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
drop policy if exists "Owners can delete their games" on public.games;
create policy "Owners can delete their games" on public.games for delete to authenticated using (auth.uid() = owner_id);

drop policy if exists "Anyone can read reviews" on public.reviews;
create policy "Anyone can read reviews" on public.reviews for select using (true);
drop policy if exists "Users can write their own reviews" on public.reviews;
create policy "Users can write their own reviews" on public.reviews for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can update their own reviews" on public.reviews;
create policy "Users can update their own reviews" on public.reviews for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Users can delete their own reviews" on public.reviews;
create policy "Users can delete their own reviews" on public.reviews for delete to authenticated using (auth.uid() = user_id);

-- Clients cannot directly alter likes. The RPC below toggles the current user's like.
drop policy if exists "Users can read their own likes" on public.game_likes;
create policy "Users can read their own likes" on public.game_likes for select to authenticated using (auth.uid() = user_id);

create or replace function public.toggle_game_like(target_game_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare removed_count integer;
begin
  if auth.uid() is null then raise exception 'ログインしてください'; end if;
  if not exists(select 1 from public.games g where g.id = target_game_id) then raise exception 'ゲームが見つかりません'; end if;
  delete from public.game_likes where game_id = target_game_id and user_id = auth.uid();
  get diagnostics removed_count = row_count;
  if removed_count = 0 then
    insert into public.game_likes(game_id,user_id) values(target_game_id,auth.uid());
    return true;
  end if;
  return false;
end;
$$;
revoke all on function public.toggle_game_like(uuid) from public;
grant execute on function public.toggle_game_like(uuid) to authenticated;

-- Count likes through a narrowly scoped SECURITY DEFINER function so public visitors
-- can see totals without being granted access to individual liker IDs.
create or replace function public.count_game_likes(target_game_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$ select count(*)::integer from public.game_likes where game_id = target_game_id; $$;
revoke all on function public.count_game_likes(uuid) from public;
grant execute on function public.count_game_likes(uuid) to anon, authenticated;

-- Public-safe views: never expose uploader email addresses or auth user IDs.
create or replace view public.games_public with (security_invoker = true) as
select g.id,g.title,g.description,g.category,g.game_url,g.cover_url,g.created_at,
       public.count_game_likes(g.id) as likes_count,
       coalesce((select round(avg(r.rating)::numeric,1) from public.reviews r where r.game_id=g.id),0)::numeric as average_rating,
       (select count(*)::integer from public.reviews r where r.game_id=g.id) as review_count
from public.games g;

grant select on public.games_public to anon, authenticated;
grant select, insert, update, delete on public.games to authenticated;
grant select on public.games to anon;
grant select on public.reviews to anon, authenticated;
grant insert, update, delete on public.reviews to authenticated;
grant select on public.game_likes to authenticated;

create or replace view public.reviews_public with (security_invoker = true) as
select r.id,r.game_id,r.rating,r.comment,r.created_at,'プレイヤー'::text as display_name
from public.reviews r;
grant select on public.reviews_public to anon, authenticated;

-- Storage buckets. Keep game HTML and covers public for play/share URLs, but uploads are authenticated and user-folder scoped.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('game-files','game-files',true,10485760,array['text/html'])
on conflict (id) do update set public=true,file_size_limit=10485760,allowed_mime_types=array['text/html'];
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('game-covers','game-covers',true,3145728,array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do update set public=true,file_size_limit=3145728,allowed_mime_types=array['image/png','image/jpeg','image/webp','image/gif'];

drop policy if exists "Authenticated users upload game html to own folder" on storage.objects;
create policy "Authenticated users upload game html to own folder" on storage.objects for insert to authenticated with check (bucket_id='game-files' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Owners can delete their game html" on storage.objects;
create policy "Owners can delete their game html" on storage.objects for delete to authenticated using (bucket_id='game-files' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Authenticated users upload covers to own folder" on storage.objects;
create policy "Authenticated users upload covers to own folder" on storage.objects for insert to authenticated with check (bucket_id='game-covers' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Owners can delete their covers" on storage.objects;
create policy "Owners can delete their covers" on storage.objects for delete to authenticated using (bucket_id='game-covers' and (storage.foldername(name))[1]=auth.uid()::text);

-- Notes:
-- * Run in a fresh Supabase project or review existing policies first.
-- * This starter does not implement moderation, abuse reporting, or malware scanning.
-- * User submitted HTML is executable code. It is served from Supabase's storage origin and embedded with a restricted sandbox.
