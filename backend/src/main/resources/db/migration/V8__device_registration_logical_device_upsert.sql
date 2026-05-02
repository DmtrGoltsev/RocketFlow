alter table device_registrations
    add column installation_id varchar(120);

create unique index device_registrations_installation_id_uq
    on device_registrations (installation_id)
    where installation_id is not null;
