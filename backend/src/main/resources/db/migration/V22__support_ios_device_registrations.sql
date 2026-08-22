alter table device_registrations
    drop constraint device_registrations_platform_chk;

alter table device_registrations
    add constraint device_registrations_platform_chk check (platform in ('android', 'ios'));
