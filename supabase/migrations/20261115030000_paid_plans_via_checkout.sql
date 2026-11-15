-- Already applied to the live nyansatek-hrms database (migration "paid_plans_via_checkout").
-- Kept here as the record of what changed.
--
-- HRMS is sold through nyansatek.systems: GHS 500 a month or GHS 5,000 a year.
-- Existing organizations keep plan_key = 'open' and are not affected by anything here.

-- ---------- payment details the browser must never see ----------------
-- Kept apart from hrms.organizations because every member of an organization can read that row.
create table if not exists hrms.org_billing (
  org_id uuid primary key references hrms.organizations(id) on delete cascade,
  plan_cycle text,
  payment_channel text check (payment_channel in ('card', 'momo')),
  paystack_authorization_code text,
  paystack_subscription_code text,
  momo_phone text,
  momo_provider text,
  sales_agent_id uuid,
  signup_reference text,
  contact_email text,
  contact_phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table hrms.org_billing enable row level security;   -- no policies on purpose: the checkout's service key only
revoke all on hrms.org_billing from anon, authenticated;
grant all on hrms.org_billing to service_role;
comment on table hrms.org_billing is 'Billing details written by the nyansatek.systems checkout. No RLS policies: not readable from the app.';

-- ---------- a paid plan lapses 7 days after its paid-through date -----
create or replace function hrms.org_usable(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from hrms.organizations o
    where o.id = p_org and o.status in ('active', 'trial')
      and (o.plan_key = 'open' or o.paid_through_date is null or o.paid_through_date >= current_date - 7)
  )
$$;

-- ---------- an owner can edit the organization, but not its plan ------
create or replace function hrms.protect_plan_fields()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon')
     and (new.plan_key, new.status, new.paid_through_date, new.trial_ends_at, new.max_employees)
         is distinct from (old.plan_key, old.status, old.paid_through_date, old.trial_ends_at, old.max_employees) then
    raise exception 'The plan can only be changed by NYANSATEK.';
  end if;
  return new;
end $$;
drop trigger if exists trg_protect_plan on hrms.organizations;
create trigger trg_protect_plan before update on hrms.organizations
  for each row execute function hrms.protect_plan_fields();

-- ---------- new organizations come from the checkout only -------------
revoke execute on function hrms.create_organization(text, text, text, text, text, text) from public, anon, authenticated;
