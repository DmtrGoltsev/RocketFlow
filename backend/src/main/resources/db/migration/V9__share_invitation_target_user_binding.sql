alter table share_invitations
    add column target_user_id uuid references users (id) on delete set null;

update share_invitations invitation
set target_user_id = users.id
from users
where lower(users.email) = lower(invitation.target_email);

create index share_invitations_target_user_id_idx on share_invitations (target_user_id, status);
