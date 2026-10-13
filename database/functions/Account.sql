-- Self-service account deletion (Apple App Store Review Guideline 5.1.1(v) /
-- Google Play data-safety account-deletion requirement) and full data export.
-- Sensitive columns below are AES-256-GCM ciphertext - those are decrypted at
-- the Provider layer, never in SQL.

-- Hard-deletes every row this user owns, then the account row itself.
-- Order matters: children before parents, though none of these FKs cascade,
-- so nothing here is strictly required by the schema - it's kept anyway so a
-- constraint added later doesn't silently break this function.
CREATE OR REPLACE FUNCTION dbo.usp_account_delete(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    -- Weekly AI plan delivery audit rows reference this user, the owned splits
    -- and the owned diet plans they delivered - all non-cascading - so they
    -- must be cleared before any of those, or deletion fails on the first FK
    -- violation.
    DELETE FROM dbo.weeklyaiplandeliveries WHERE userid = p_userid;

    DELETE FROM dbo.workoutsetlogs WHERE userid = p_userid;
    DELETE FROM dbo.workoutsessions WHERE userid = p_userid;
    DELETE FROM dbo.useractivesplits WHERE userid = p_userid;
    DELETE FROM dbo.splitassignments WHERE userid = p_userid;
    DELETE FROM dbo.useractivedietplans WHERE userid = p_userid;
    DELETE FROM dbo.dietplanassignments WHERE userid = p_userid;

    -- Owned-split tree: exercises -> days -> the split rows themselves, for
    -- every split this user built via the in-app builder.
    DELETE FROM dbo.splitdayexercises sde
    USING dbo.splitdays sd, dbo.workoutsplits ws
    WHERE sd.splitdayid = sde.splitdayid
      AND ws.splitid = sd.splitid
      AND ws.owneruserid = p_userid;

    DELETE FROM dbo.splitdays sd
    USING dbo.workoutsplits ws
    WHERE ws.splitid = sd.splitid
      AND ws.owneruserid = p_userid;

    DELETE FROM dbo.workoutsplits WHERE owneruserid = p_userid;

    -- Private exercises this user added from the picker. After their set
    -- logs and owned split days above - the only rows that can point at them,
    -- since usp_UserSplitDayExercise_Upsert won't take another user's exercise.
    DELETE FROM dbo.exercises WHERE createdbyuserid = p_userid;

    -- Owned-diet-plan tree: meals -> days -> the plan rows themselves, for
    -- every plan this user built via the app.
    DELETE FROM dbo.dietplanmeals dpm
    USING dbo.dietplandays dpd, dbo.nutritionplans dp
    WHERE dpd.dietplandayid = dpm.dietplandayid
      AND dp.dietplanid = dpd.dietplanid
      AND dp.owneruserid = p_userid;

    DELETE FROM dbo.dietplandays dpd
    USING dbo.nutritionplans dp
    WHERE dp.dietplanid = dpd.dietplanid
      AND dp.owneruserid = p_userid;

    DELETE FROM dbo.nutritionplans WHERE owneruserid = p_userid;

    -- Meals this user built from ingredients; their ingredient lines
    -- cascade. After the owned plan tree above - the only rows pointing here.
    DELETE FROM dbo.mealsuggestions WHERE owneruserid = p_userid;

    DELETE FROM dbo.hydrationlogs WHERE userid = p_userid;
    DELETE FROM dbo.bodyweightlogs WHERE userid = p_userid;
    DELETE FROM dbo.meallogs WHERE userid = p_userid;
    -- Private foods this user added to the catalog while logging meals.
    DELETE FROM dbo.foodnutrition WHERE createdbyuserid = p_userid;
    -- AI food-scan allowance ledger - timestamps only.
    DELETE FROM dbo.foodscans WHERE userid = p_userid;
    DELETE FROM dbo.usernutritiontargets WHERE userid = p_userid;
    DELETE FROM dbo.usersubscriptions WHERE userid = p_userid;
    -- After UserSubscriptions (its LatestReceiptId points here). Also frees the
    -- store subscription so the same Apple/Google account can restore it onto
    -- a new Silen account (see usp_SubscriptionReceipt_GetOwner).
    DELETE FROM dbo.subscriptionreceipts WHERE userid = p_userid;
    DELETE FROM dbo.monthlyreviewdeliveries WHERE userid = p_userid;
    DELETE FROM dbo.monthlyanalyticsreports WHERE userid = p_userid;
    DELETE FROM dbo.weeklyanalyticsreports WHERE userid = p_userid;
    DELETE FROM dbo.userdevicetokens WHERE userid = p_userid;
    DELETE FROM dbo.usernotifications WHERE userid = p_userid;
    DELETE FROM dbo.usernotificationstates WHERE userid = p_userid;
    DELETE FROM dbo.userprofiles WHERE userid = p_userid;
    DELETE FROM dbo.usersettings WHERE userid = p_userid;
    DELETE FROM dbo.userauthidentities WHERE userid = p_userid;
    DELETE FROM dbo.pendingemailverifications WHERE existinguserid = p_userid;
    DELETE FROM dbo.users WHERE userid = p_userid;
END $$;

-- Removes abandoned guest accounts: an app install that never signed up, never
-- logged anything and has not been back for p_idledays. Concretely: AccountTier
-- 'Guest', no email, no sign-in identity other than its Device one, no workouts,
-- meals, hydration or bodyweight, no subscription or store receipt, and a last
-- login (or creation) older than p_idledays. These show up as "Unnamed user" in
-- the console's user list. If that device opens the app again it simply starts
-- over as a new guest - there was nothing to lose.
--
-- Each one goes through usp_Account_Delete so every dependent row is cleared in
-- the same order a real account deletion uses. p_dryrun = true only lists what
-- would be deleted.
CREATE OR REPLACE FUNCTION dbo.usp_account_pruneorphanguests(
    p_idledays integer DEFAULT 7,
    p_dryrun boolean DEFAULT true
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_cutoff timestamp(3) := dbo.sysutcdatetime() - make_interval(days => p_idledays);
    v_orphans uuid[];
    v_userid uuid;
    v_deleted integer := 0;
BEGIN
    v_orphans := ARRAY(
        SELECT u.userid
        FROM dbo.users u
        WHERE u.accounttier = 'Guest'
          AND u.email IS NULL
          AND COALESCE(u.lastloginatutc, u.createdatutc) < v_cutoff
          AND NOT EXISTS (SELECT 1 FROM dbo.userauthidentities i WHERE i.userid = u.userid AND i.provider <> 'Device')
          AND NOT EXISTS (SELECT 1 FROM dbo.workoutsessions w WHERE w.userid = u.userid)
          AND NOT EXISTS (SELECT 1 FROM dbo.meallogs m WHERE m.userid = u.userid)
          AND NOT EXISTS (SELECT 1 FROM dbo.hydrationlogs h WHERE h.userid = u.userid)
          AND NOT EXISTS (SELECT 1 FROM dbo.bodyweightlogs b WHERE b.userid = u.userid)
          AND NOT EXISTS (SELECT 1 FROM dbo.usersubscriptions s WHERE s.userid = u.userid)
          AND NOT EXISTS (SELECT 1 FROM dbo.subscriptionreceipts r WHERE r.userid = u.userid));

    IF p_dryrun THEN
        OPEN c1 FOR
        SELECT userid, createdatutc, lastloginatutc
        FROM dbo.users
        WHERE userid = ANY (v_orphans)
        ORDER BY createdatutc;
        RETURN NEXT c1;
        RETURN;
    END IF;

    FOREACH v_userid IN ARRAY v_orphans LOOP
        PERFORM dbo.usp_account_delete(v_userid);
        v_deleted := v_deleted + 1;
    END LOOP;

    OPEN c1 FOR SELECT v_deleted AS deletedusers;
    RETURN NEXT c1;
END $$;

-- Atomically checks and, if allowed, stamps dbo.users.lastexportrequestedatutc
-- so at most one export can be requested per p_cooldowndays - a "download my
-- data" export decrypts and emails a user's entire history, so it needs the
-- same per-user cooldown discipline as PendingEmailVerifications.LastSentAtUtc,
-- just with a much longer window. FOR UPDATE on the read serializes concurrent
-- requests from the same user so two simultaneous calls can't both read
-- "allowed" before either writes the new timestamp.
CREATE OR REPLACE FUNCTION dbo.usp_account_trybeginexport(
    p_userid uuid,
    p_cooldowndays integer
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
    v_now timestamp(3) := dbo.sysutcdatetime();
    v_lastrequestedatutc timestamp(3);
BEGIN
    SELECT lastexportrequestedatutc INTO v_lastrequestedatutc
    FROM dbo.users
    WHERE userid = p_userid
    FOR UPDATE;

    IF v_lastrequestedatutc IS NOT NULL AND v_lastrequestedatutc + make_interval(days => p_cooldowndays) > v_now THEN
        OPEN c1 FOR SELECT false AS allowed, (v_lastrequestedatutc + make_interval(days => p_cooldowndays))::timestamp(3) AS nextallowedatutc;
        RETURN NEXT c1;
        RETURN;
    END IF;

    UPDATE dbo.users SET lastexportrequestedatutc = v_now WHERE userid = p_userid;

    OPEN c1 FOR SELECT true AS allowed, NULL::timestamp(3) AS nextallowedatutc;
    RETURN NEXT c1;
END $$;

-- Full "download my data" export: one result set per section, read in this
-- exact order by AccountProvider.ExportAsync via SqlResultSetReader. Column
-- lists mirror each feature's own Get function so the existing row mappers
-- (UserProfileRowMapper/SettingsRowMapper/MealPlanningRowMapper/
-- WorkoutRowMapper) can be reused as-is; only the sections with no prior
-- "get everything for this user" function (identities, hydration history,
-- workout-session history, set-log history) are new SELECTs.
CREATE OR REPLACE FUNCTION dbo.usp_account_export(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor; c2 refcursor; c3 refcursor; c4 refcursor; c5 refcursor; c6 refcursor;
    c7 refcursor; c8 refcursor; c9 refcursor; c10 refcursor; c11 refcursor;
BEGIN
    -- 1: Account
    OPEN c1 FOR
    SELECT userid, deviceid, displayname, email, accounttier, createdatutc, lastloginatutc, isactive
    FROM dbo.users
    WHERE userid = p_userid;
    RETURN NEXT c1;

    -- 2: Linked sign-in identities
    OPEN c2 FOR
    SELECT provider, externalid, createdatutc
    FROM dbo.userauthidentities
    WHERE userid = p_userid
    ORDER BY createdatutc ASC;
    RETURN NEXT c2;

    -- 3: Profile
    OPEN c3 FOR
    SELECT userid, gender, ageyears, heightcm, weightkg, goal,
           trainingdaysperweek, sessiondurationminutes, trainingexperience, equipmentaccess, dailyactivitylevel,
           createdatutc, updatedatutc
    FROM dbo.userprofiles
    WHERE userid = p_userid;
    RETURN NEXT c3;

    -- 4: Settings
    OPEN c4 FOR
    SELECT userid, targetwaterml, notificationsenabled, notificationlocaltime, timezoneid,
           weightunit, distanceunit, resttimersoundenabled, barbellstandardkg, appearancemode,
           avatarchoice, aidataconsentatutc, updatedatutc
    FROM dbo.usersettings
    WHERE userid = p_userid;
    RETURN NEXT c4;

    -- 5: Nutrition targets
    OPEN c5 FOR
    SELECT userid, targetcalories, targetproteing, targetcarbsg, targetfatsg, ismanualoverride, updatedatutc
    FROM dbo.usernutritiontargets
    WHERE userid = p_userid;
    RETURN NEXT c5;

    -- 6: Bodyweight history
    OPEN c6 FOR
    SELECT bodyweightlogid, weightkg, loggedatutc
    FROM dbo.bodyweightlogs
    WHERE userid = p_userid
    ORDER BY loggedatutc ASC;
    RETURN NEXT c6;

    -- 7: Hydration history
    OPEN c7 FOR
    SELECT hydrationlogid, amountml, loggedatutc
    FROM dbo.hydrationlogs
    WHERE userid = p_userid
    ORDER BY loggedatutc ASC;
    RETURN NEXT c7;

    -- 8: Meal logs
    OPEN c8 FOR
    SELECT meallogid, userid, logdateutc, mealtype, title, calorieskcal, proteing, carbsg, fatsg, items,
           status, plannedlocaltime, loggedatutc, createdatutc
    FROM dbo.meallogs
    WHERE userid = p_userid
    ORDER BY logdateutc ASC, createdatutc ASC;
    RETURN NEXT c8;

    -- 9: Workout session history
    OPEN c9 FOR
    SELECT workoutsessionid, scheduleddateutc, status, startedatutc, completedatutc,
           durationminutes, caloriesestimate, rpescore, tonnagekg, createdatutc
    FROM dbo.workoutsessions
    WHERE userid = p_userid
    ORDER BY scheduleddateutc ASC;
    RETURN NEXT c9;

    -- 10: Workout set-log history
    OPEN c10 FOR
    SELECT workoutsetlogid, workoutsessionid, exerciseid, setnumber, weightkg, reps, completedatutc
    FROM dbo.workoutsetlogs
    WHERE userid = p_userid
    ORDER BY completedatutc ASC;
    RETURN NEXT c10;

    -- 11: Active subscription
    OPEN c11 FOR
    SELECT userid, planid, billingcycle, status, startedatutc, expiresatutc
    FROM dbo.usersubscriptions
    WHERE userid = p_userid;
    RETURN NEXT c11;
END $$;

-- Stores the (encrypted) Sign in with Apple refresh token on the user's
-- Apple identity, so account deletion can revoke it with Apple.
CREATE OR REPLACE FUNCTION dbo.usp_account_setapplerefreshtoken(
    p_userid uuid,
    p_refreshtokenciphertext bytea
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
BEGIN
    UPDATE dbo.userauthidentities
    SET refreshtokenciphertext = p_refreshtokenciphertext
    WHERE userid = p_userid AND provider = 'Apple';
END $$;

CREATE OR REPLACE FUNCTION dbo.usp_account_getapplerefreshtoken(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT refreshtokenciphertext
    FROM dbo.userauthidentities
    WHERE userid = p_userid AND provider = 'Apple' AND refreshtokenciphertext IS NOT NULL;
    RETURN NEXT c1;
END $$;
