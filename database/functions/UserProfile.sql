CREATE OR REPLACE FUNCTION dbo.usp_userprofile_get(
    p_userid uuid
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    OPEN c1 FOR
    SELECT userid, gender, ageyears, heightcm, weightkg, goal, trainingdaysperweek, sessiondurationminutes, trainingexperience, equipmentaccess, dailyactivitylevel, createdatutc, updatedatutc
    FROM dbo.userprofiles
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;

-- Gender/AgeYears/HeightCm/WeightKg/Goal are AES-256-GCM ciphertext
-- (Silen.Common.Helpers.FieldCipher) - encrypted/decrypted at the
-- UserProfileProvider layer, so these params are opaque bytea here and the
-- checks that used to validate Gender/Goal text live in
-- UserProfileService.Validate() instead.
CREATE OR REPLACE FUNCTION dbo.usp_userprofile_upsert(
    p_userid uuid,
    p_gender bytea,
    p_ageyears bytea,
    p_heightcm bytea,
    p_weightkg bytea,
    p_goal bytea,
    p_trainingdaysperweek bytea DEFAULT NULL,
    p_sessiondurationminutes bytea DEFAULT NULL,
    p_trainingexperience bytea DEFAULT NULL,
    p_equipmentaccess bytea DEFAULT NULL,
    p_dailyactivitylevel bytea DEFAULT NULL
) RETURNS SETOF refcursor LANGUAGE plpgsql AS $$
DECLARE
    c1 refcursor;
BEGIN
    INSERT INTO dbo.userprofiles AS t (userid, gender, ageyears, heightcm, weightkg, goal, trainingdaysperweek, sessiondurationminutes, trainingexperience, equipmentaccess, dailyactivitylevel)
    VALUES (p_userid, p_gender, p_ageyears, p_heightcm, p_weightkg, p_goal, p_trainingdaysperweek, p_sessiondurationminutes, p_trainingexperience, p_equipmentaccess, p_dailyactivitylevel)
    ON CONFLICT (userid) DO UPDATE SET
        gender = p_gender,
        ageyears = p_ageyears,
        heightcm = p_heightcm,
        weightkg = p_weightkg,
        goal = p_goal,
        trainingdaysperweek = COALESCE(p_trainingdaysperweek, t.trainingdaysperweek),
        sessiondurationminutes = COALESCE(p_sessiondurationminutes, t.sessiondurationminutes),
        trainingexperience = COALESCE(p_trainingexperience, t.trainingexperience),
        equipmentaccess = COALESCE(p_equipmentaccess, t.equipmentaccess),
        dailyactivitylevel = COALESCE(p_dailyactivitylevel, t.dailyactivitylevel),
        updatedatutc = dbo.sysutcdatetime();

    OPEN c1 FOR
    SELECT userid, gender, ageyears, heightcm, weightkg, goal, trainingdaysperweek, sessiondurationminutes, trainingexperience, equipmentaccess, dailyactivitylevel, createdatutc, updatedatutc
    FROM dbo.userprofiles
    WHERE userid = p_userid;
    RETURN NEXT c1;
END $$;
