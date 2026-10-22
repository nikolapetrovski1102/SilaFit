CREATE OR REPLACE FUNCTION dbo.usp_usersettings_get(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT s.userid, s.targetwaterml, s.notificationsenabled, s.notificationlocaltime,
           s.notificationtimeisuserset, s.timezoneid,
           s.weightunit, s.distanceunit, s.resttimersoundenabled, s.appearancemode,
           s.avatarchoice, s.aidataconsentatutc, s.updatedatutc,
           -- Feeds the "Auto" reminder time shown in Settings (see ReminderTimeDetector).
           (SELECT array_agg(w.startedatutc)
            FROM dbo.workoutsessions w
            WHERE w.userid = s.userid
              AND w.startedatutc >= dbo.sysutcdatetime() - interval '28 days') AS recentworkoutstartsutc
    FROM dbo.usersettings s
    WHERE s.userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usersettings_setnotificationsenabled(
    p_userid uuid,
    p_notificationsenabled boolean
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.usersettings
    SET notificationsenabled = p_notificationsenabled,
        updatedatutc = dbo.sysutcdatetime()
    WHERE userid = p_userid;
END $$;

-- Grants (stamps now) or revokes (clears) consent to share the user's data
-- with the third-party AI provider. Kept out of usp_UserSettings_Update so a
-- plain settings save can never flip it by accident.
CREATE OR REPLACE FUNCTION dbo.usp_usersettings_setaidataconsent(
    p_userid uuid,
    p_granted boolean
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    UPDATE dbo.usersettings
    SET aidataconsentatutc = CASE WHEN p_granted THEN COALESCE(aidataconsentatutc, dbo.sysutcdatetime()) ELSE NULL END,
        updatedatutc = dbo.sysutcdatetime()
    WHERE userid = p_userid;

    OPEN c1 FOR
    SELECT s.userid, s.targetwaterml, s.notificationsenabled, s.notificationlocaltime,
           s.notificationtimeisuserset, s.timezoneid,
           s.weightunit, s.distanceunit, s.resttimersoundenabled, s.appearancemode,
           s.avatarchoice, s.aidataconsentatutc, s.updatedatutc,
           -- Feeds the "Auto" reminder time shown in Settings (see ReminderTimeDetector).
           (SELECT array_agg(w.startedatutc)
            FROM dbo.workoutsessions w
            WHERE w.userid = s.userid
              AND w.startedatutc >= dbo.sysutcdatetime() - interval '28 days') AS recentworkoutstartsutc
    FROM dbo.usersettings s
    WHERE s.userid = p_userid;
    RETURN NEXT c1;
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_usersettings_update(
    p_userid uuid,
    p_targetwaterml integer,
    p_notificationsenabled boolean,
    p_notificationlocaltime time(0),
    p_timezoneid varchar(100),
    p_weightunit varchar(3),
    p_distanceunit varchar(3),
    p_resttimersoundenabled boolean,
    p_appearancemode varchar(10),
    p_avatarchoice varchar(10),
    p_notificationtimeisuserset boolean DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    UPDATE dbo.usersettings
    SET targetwaterml = p_targetwaterml,
        notificationsenabled = p_notificationsenabled,
        notificationlocaltime = p_notificationlocaltime,
        -- NULL comes from app builds that predate the flag: keep it, but treat a
        -- changed time as the user choosing one.
        notificationtimeisuserset = COALESCE(
            p_notificationtimeisuserset,
            notificationtimeisuserset OR notificationlocaltime <> p_notificationlocaltime),
        timezoneid = p_timezoneid,
        weightunit = p_weightunit,
        distanceunit = p_distanceunit,
        resttimersoundenabled = p_resttimersoundenabled,
        appearancemode = p_appearancemode,
        avatarchoice = p_avatarchoice,
        updatedatutc = dbo.sysutcdatetime()
    WHERE userid = p_userid;

    OPEN c1 FOR
    SELECT s.userid, s.targetwaterml, s.notificationsenabled, s.notificationlocaltime,
           s.notificationtimeisuserset, s.timezoneid,
           s.weightunit, s.distanceunit, s.resttimersoundenabled, s.appearancemode,
           s.avatarchoice, s.aidataconsentatutc, s.updatedatutc,
           -- Feeds the "Auto" reminder time shown in Settings (see ReminderTimeDetector).
           (SELECT array_agg(w.startedatutc)
            FROM dbo.workoutsessions w
            WHERE w.userid = s.userid
              AND w.startedatutc >= dbo.sysutcdatetime() - interval '28 days') AS recentworkoutstartsutc
    FROM dbo.usersettings s
    WHERE s.userid = p_userid;
    RETURN NEXT c1;
END $$;
