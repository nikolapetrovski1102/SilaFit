-- Baseline, part 1: database objects and bare tables (columns, defaults, primary keys).
-- Generated from the SQL Server production schema at the PostgreSQL move. Part 2
-- (0002) adds indexes, checks and foreign keys; the data copy runs between the two.

-- Database-level objects every other script depends on.
CREATE SCHEMA IF NOT EXISTS dbo;

-- Case-insensitive, accent-sensitive comparisons, matching SQL_Latin1_General_CP1_CI_AS.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_collation WHERE collname = 'ci' AND collnamespace = 'public'::regnamespace) THEN
        CREATE COLLATION public.ci (provider = icu, locale = 'und-u-ks-level2', deterministic = false);
    END IF;
END $$;

-- UTC "now" as timestamp without time zone, the equivalent of SQL Server SYSUTCDATETIME().
CREATE OR REPLACE FUNCTION dbo.sysutcdatetime() RETURNS timestamp
LANGUAGE sql STABLE PARALLEL SAFE
AS $$ SELECT (statement_timestamp() AT TIME ZONE 'UTC')::timestamp $$;

-- The Outcome/EntityId/Detail result set every CRUD function returns
-- (0 = ok, 1 = not found, 2 = forbidden/conflict, 3 = validation). Opens and
-- returns the cursor so callers can `RETURN NEXT dbo.outcome_cursor(...)`.
CREATE OR REPLACE FUNCTION dbo.outcome_cursor(p_outcome integer, p_entityid uuid, p_detail text)
RETURNS refcursor LANGUAGE plpgsql AS $$
DECLARE
    c refcursor;
BEGIN
    OPEN c FOR SELECT p_outcome AS outcome, p_entityid AS entityid, p_detail AS detail;
    RETURN c;
END $$;


CREATE TABLE dbo._bak_exercises_028 (
    exerciseid uuid NOT NULL,
    name varchar(150) COLLATE ci NOT NULL,
    musclegroup varchar(30) COLLATE ci NOT NULL,
    equipmenttype varchar(50) COLLATE ci,
    iscompound boolean NOT NULL,
    demovideourl varchar(500) COLLATE ci,
    createdatutc timestamp(3) NOT NULL
);

CREATE TABLE dbo._bak_splitdayexercises_028 (
    splitdayexerciseid uuid NOT NULL,
    exerciseid uuid NOT NULL,
    backedupatutc timestamp(6) NOT NULL
);

CREATE TABLE dbo._bak_workoutsetlogs_028 (
    workoutsetlogid uuid NOT NULL,
    exerciseid uuid NOT NULL,
    backedupatutc timestamp(6) NOT NULL
);

CREATE TABLE dbo.adminauditlog (
    auditid uuid DEFAULT uuidv7() NOT NULL,
    adminuserid uuid,
    username varchar(100) COLLATE ci NOT NULL,
    action varchar(30) COLLATE ci NOT NULL,
    entitytype varchar(50) COLLATE ci NOT NULL,
    entityid varchar(64) COLLATE ci,
    summary varchar(500) COLLATE ci,
    createdfromip varchar(64) COLLATE ci,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_adminauditlog PRIMARY KEY (auditid)
);

CREATE TABLE dbo.adminrolepermissions (
    roleid uuid NOT NULL,
    permission varchar(64) COLLATE ci NOT NULL,
    CONSTRAINT pk_adminrolepermissions PRIMARY KEY (roleid, permission)
);

CREATE TABLE dbo.adminroles (
    roleid uuid DEFAULT uuidv7() NOT NULL,
    name varchar(64) COLLATE ci NOT NULL,
    description varchar(300) COLLATE ci,
    issystemrole boolean DEFAULT false NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_adminroles PRIMARY KEY (roleid)
);

CREATE TABLE dbo.adminsessions (
    adminsessionid uuid DEFAULT uuidv7() NOT NULL,
    adminuserid uuid NOT NULL,
    tokenhash bytea NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    lastseenatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    expiresatutc timestamp(3) NOT NULL,
    absoluteexpiresatutc timestamp(3) NOT NULL,
    createdfromip varchar(64) COLLATE ci,
    CONSTRAINT pk_adminsessions PRIMARY KEY (adminsessionid)
);

CREATE TABLE dbo.adminusers (
    adminuserid uuid DEFAULT uuidv7() NOT NULL,
    username varchar(100) COLLATE ci NOT NULL,
    passwordhash bytea NOT NULL,
    passwordsalt bytea NOT NULL,
    totpsecretcipher bytea NOT NULL,
    failedattemptcount integer DEFAULT 0 NOT NULL,
    lockeduntilutc timestamp(3),
    lastloginatutc timestamp(3),
    passwordchangedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    roleid uuid,
    email varchar(256) COLLATE ci,
    emailotpcodehash bytea,
    emailotpcodesalt bytea,
    emailotpexpiresatutc timestamp(3),
    emailotplastsentatutc timestamp(3),
    emailconfirmedatutc timestamp(3),
    CONSTRAINT pk_adminusers PRIMARY KEY (adminuserid)
);

CREATE TABLE dbo.aiprompttemplates (
    prompttemplateid uuid DEFAULT uuidv7() NOT NULL,
    templatekey varchar(50) COLLATE ci NOT NULL,
    systemprompt text COLLATE ci NOT NULL,
    userprompttemplate text COLLATE ci NOT NULL,
    model varchar(100) COLLATE ci NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_aiprompttemplates PRIMARY KEY (prompttemplateid)
);

CREATE TABLE dbo.bodyweightlogs (
    bodyweightlogid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    loggedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    weightkg_legacy numeric(5,2),
    weightkg bytea,
    CONSTRAINT pk_bodyweightlogs PRIMARY KEY (bodyweightlogid)
);

CREATE TABLE dbo.dietplanassignments (
    dietplanid uuid NOT NULL,
    userid uuid NOT NULL,
    assignedbyadminuserid uuid,
    assignedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_dietplanassignments PRIMARY KEY (dietplanid, userid)
);

CREATE TABLE dbo.dietplandays (
    dietplandayid uuid DEFAULT gen_random_uuid() NOT NULL,
    dietplanid uuid NOT NULL,
    dayindex smallint NOT NULL,
    title varchar(200) COLLATE ci,
    CONSTRAINT pk_dietplandays PRIMARY KEY (dietplandayid)
);

CREATE TABLE dbo.dietplanmeals (
    dietplanmealid uuid DEFAULT gen_random_uuid() NOT NULL,
    dietplandayid uuid NOT NULL,
    mealtype varchar(20) COLLATE ci NOT NULL,
    mealsuggestionid uuid NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    CONSTRAINT pk_dietplanmeals PRIMARY KEY (dietplanmealid)
);

CREATE TABLE dbo.dietplans (
    dietplanid uuid DEFAULT uuidv7() NOT NULL,
    title varchar(200) COLLATE ci NOT NULL,
    summary varchar(1000) COLLATE ci,
    contenttext text COLLATE ci NOT NULL,
    imageurl varchar(500) COLLATE ci,
    sourceurl varchar(500) COLLATE ci NOT NULL,
    sourceauthor varchar(300) COLLATE ci,
    issystemdefault boolean DEFAULT true NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_dietplans PRIMARY KEY (dietplanid)
);

CREATE TABLE dbo.dietplansections (
    dietplansectionid uuid DEFAULT uuidv7() NOT NULL,
    dietplanid uuid NOT NULL,
    sortorder smallint NOT NULL,
    heading varchar(500) COLLATE ci,
    bodytext text COLLATE ci,
    listsjson text COLLATE ci,
    tablesjson text COLLATE ci,
    CONSTRAINT pk_dietplansections PRIMARY KEY (dietplansectionid)
);

CREATE TABLE dbo.exercises (
    exerciseid uuid DEFAULT uuidv7() NOT NULL,
    name varchar(150) COLLATE ci NOT NULL,
    musclegroup varchar(30) COLLATE ci NOT NULL,
    equipmenttype varchar(50) COLLATE ci,
    iscompound boolean DEFAULT false NOT NULL,
    demovideourl varchar(500) COLLATE ci,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    createdbyuserid uuid,
    CONSTRAINT pk_exercises PRIMARY KEY (exerciseid)
);

CREATE TABLE dbo.foodnutrition (
    foodnutritionid bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    name varchar(500) COLLATE ci NOT NULL,
    normalizedname varchar(500) COLLATE "C" NOT NULL,
    brandname varchar(300) COLLATE ci,
    barcode varchar(80) COLLATE ci,
    datatype varchar(50) COLLATE ci,
    sourcename varchar(40) COLLATE ci NOT NULL,
    sourcefoodid varchar(120) COLLATE ci NOT NULL,
    sourceurl varchar(1000) COLLATE ci,
    servingsizeg numeric(12,3),
    calorieskcal numeric(12,3),
    proteing numeric(12,3),
    carbohydrateg numeric(12,3),
    fatg numeric(12,3),
    fiberg numeric(12,3),
    sugarg numeric(12,3),
    sodiummg numeric(12,3),
    isbranded boolean DEFAULT false NOT NULL,
    contenthash bytea NOT NULL,
    sourcepriority smallint GENERATED ALWAYS AS ((CASE sourcename when 'USDA Foundation' then (0) when 'USDA Survey' then (1) when 'CNF' then (2) when 'CoFID' then (3) when 'USDA Legacy' then (4) when 'USDA Branded' then (5) when 'Open Food Facts' then (6) else (7) END)::smallint) STORED,
    namelength smallint GENERATED ALWAYS AS (char_length(rtrim(name, ' '))::smallint) STORED,
    importedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    createdbyuserid uuid,
    CONSTRAINT pk_foodnutrition PRIMARY KEY (foodnutritionid)
);

CREATE TABLE dbo.foodscans (
    foodscanid bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
    userid uuid NOT NULL,
    scannedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_foodscans PRIMARY KEY (foodscanid)
);

CREATE TABLE dbo.hydrationlogs (
    hydrationlogid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    loggedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    amountml smallint NOT NULL,
    CONSTRAINT pk_hydrationlogs PRIMARY KEY (hydrationlogid)
);

CREATE TABLE dbo.meallogs (
    meallogid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    logdateutc date NOT NULL,
    mealtype varchar(20) COLLATE ci NOT NULL,
    title_legacy varchar(200) COLLATE ci,
    calorieskcal_legacy smallint,
    proteing_legacy smallint,
    carbsg_legacy smallint,
    fatsg_legacy smallint,
    status varchar(10) COLLATE ci DEFAULT 'Planned' NOT NULL,
    plannedlocaltime time(0),
    loggedatutc timestamp(3),
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    title bytea,
    calorieskcal bytea,
    proteing bytea,
    carbsg bytea,
    fatsg bytea,
    items bytea,
    CONSTRAINT pk_meallogs PRIMARY KEY (meallogid)
);

CREATE TABLE dbo.mealsuggestioningredients (
    mealsuggestioningredientid uuid DEFAULT uuidv7() NOT NULL,
    mealsuggestionid uuid NOT NULL,
    sortorder smallint NOT NULL,
    ingredienttext varchar(1000) COLLATE ci NOT NULL,
    CONSTRAINT pk_mealsuggestioningredients PRIMARY KEY (mealsuggestioningredientid)
);

CREATE TABLE dbo.mealsuggestioninstructions (
    mealsuggestioninstructionid uuid DEFAULT uuidv7() NOT NULL,
    mealsuggestionid uuid NOT NULL,
    sortorder smallint NOT NULL,
    instructiontext varchar(2000) COLLATE ci NOT NULL,
    CONSTRAINT pk_mealsuggestioninstructions PRIMARY KEY (mealsuggestioninstructionid)
);

CREATE TABLE dbo.mealsuggestions (
    mealsuggestionid uuid DEFAULT uuidv7() NOT NULL,
    title varchar(200) COLLATE ci NOT NULL,
    mealtype varchar(20) COLLATE ci NOT NULL,
    description varchar(500) COLLATE ci,
    calorieskcal smallint NOT NULL,
    proteing smallint NOT NULL,
    carbsg smallint NOT NULL,
    fatsg smallint NOT NULL,
    suggestedmonth smallint,
    issystemdefault boolean DEFAULT true NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    sourceurl varchar(500) COLLATE ci,
    imageurl varchar(500) COLLATE ci,
    servingsuggestion varchar(1000) COLLATE ci,
    contenttext text COLLATE ci,
    categoriesjson text COLLATE ci,
    sourcemacrosjson varchar(1000) COLLATE ci,
    readcount integer,
    owneruserid uuid,
    CONSTRAINT pk_mealsuggestions PRIMARY KEY (mealsuggestionid)
);

CREATE TABLE dbo.monthlyanalyticsreports (
    reportid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    reportyear smallint NOT NULL,
    reportmonth smallint NOT NULL,
    snapshotjson text COLLATE ci NOT NULL,
    resultjson text COLLATE ci NOT NULL,
    generatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_monthlyanalyticsreports PRIMARY KEY (reportid)
);

CREATE TABLE dbo.monthlyreviewdeliveries (
    deliveryid uuid NOT NULL,
    runid uuid NOT NULL,
    userid uuid NOT NULL,
    periodyear smallint NOT NULL,
    periodmonth smallint NOT NULL,
    status varchar(20) COLLATE ci NOT NULL,
    errormessage varchar(1000) COLLATE ci,
    generatedatutc timestamp(3),
    emailedatutc timestamp(3),
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    deliverykind varchar(20) COLLATE ci DEFAULT 'Subscriber' NOT NULL,
    CONSTRAINT pk_monthlyreviewdeliveries PRIMARY KEY (deliveryid)
);

CREATE TABLE dbo.monthlyreviewruns (
    runid uuid NOT NULL,
    periodyear smallint NOT NULL,
    periodmonth smallint NOT NULL,
    plancode varchar(30) COLLATE ci NOT NULL,
    status varchar(20) COLLATE ci DEFAULT 'Running' NOT NULL,
    usersconsidered integer DEFAULT 0 NOT NULL,
    reportsgenerated integer DEFAULT 0 NOT NULL,
    emailssent integer DEFAULT 0 NOT NULL,
    failures integer DEFAULT 0 NOT NULL,
    startedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    completedatutc timestamp(3),
    CONSTRAINT pk_monthlyreviewruns PRIMARY KEY (runid)
);

CREATE TABLE dbo.nutritionplans (
    dietplanid uuid DEFAULT gen_random_uuid() NOT NULL,
    name varchar(200) COLLATE ci NOT NULL,
    description varchar(1000) COLLATE ci,
    heroimageurl varchar(500) COLLATE ci,
    periodtype varchar(20) COLLATE ci DEFAULT 'Weekly' NOT NULL,
    durationdays smallint DEFAULT 7 NOT NULL,
    issystemdefault boolean DEFAULT false NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    owneradminuserid uuid,
    owneruserid uuid,
    visibility varchar(20) COLLATE ci DEFAULT 'Public' NOT NULL,
    isaigenerated boolean DEFAULT false NOT NULL,
    aikeptatutc timestamp(3),
    CONSTRAINT pk_nutritionplans PRIMARY KEY (dietplanid)
);

CREATE TABLE dbo.pendingemailverifications (
    pendingid uuid NOT NULL,
    existinguserid uuid,
    email varchar(256) COLLATE ci NOT NULL,
    passwordhash bytea NOT NULL,
    passwordsalt bytea NOT NULL,
    displayname varchar(100) COLLATE ci,
    codehash bytea NOT NULL,
    codesalt bytea NOT NULL,
    attemptcount integer DEFAULT 0 NOT NULL,
    expiresatutc timestamp(3) NOT NULL,
    lastsentatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_pendingemailverifications PRIMARY KEY (pendingid)
);

CREATE TABLE dbo.planentitlements (
    planid uuid NOT NULL,
    maxactivesplits integer,
    maxactivedietplans integer,
    allowaigeneration boolean DEFAULT false NOT NULL,
    CONSTRAINT pk_planentitlements PRIMARY KEY (planid)
);

CREATE TABLE dbo.planfeatures (
    planfeatureid uuid DEFAULT uuidv7() NOT NULL,
    planid uuid NOT NULL,
    featuretext varchar(300) COLLATE ci NOT NULL,
    sortorder smallint DEFAULT 0 NOT NULL,
    ishighlighted boolean DEFAULT false NOT NULL,
    CONSTRAINT pk_planfeatures PRIMARY KEY (planfeatureid)
);

CREATE TABLE dbo.splitassignments (
    splitid uuid NOT NULL,
    userid uuid NOT NULL,
    assignedbyadminuserid uuid,
    assignedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_splitassignments PRIMARY KEY (splitid, userid)
);

CREATE TABLE dbo.splitdayexercises (
    splitdayexerciseid uuid DEFAULT uuidv7() NOT NULL,
    splitdayid uuid NOT NULL,
    exerciseid uuid NOT NULL,
    sortorder smallint NOT NULL,
    targetsets smallint NOT NULL,
    targetrepslow smallint NOT NULL,
    targetrepshigh smallint NOT NULL,
    sourcesets varchar(100) COLLATE ci,
    sourcereps varchar(300) COLLATE ci,
    CONSTRAINT pk_splitdayexercises PRIMARY KEY (splitdayexerciseid)
);

CREATE TABLE dbo.splitdays (
    splitdayid uuid DEFAULT uuidv7() NOT NULL,
    splitid uuid NOT NULL,
    dayindex smallint NOT NULL,
    title varchar(150) COLLATE ci NOT NULL,
    focuslabel varchar(100) COLLATE ci,
    estimatedminutes smallint DEFAULT 45 NOT NULL,
    isrestday boolean DEFAULT false NOT NULL,
    sourcenotes text COLLATE ci,
    CONSTRAINT pk_splitdays PRIMARY KEY (splitdayid)
);

CREATE TABLE dbo.subscriptionplans (
    planid uuid DEFAULT uuidv7() NOT NULL,
    code varchar(30) COLLATE ci NOT NULL,
    name varchar(100) COLLATE ci NOT NULL,
    tagline varchar(300) COLLATE ci,
    monthlyprice numeric(9,2) NOT NULL,
    yearlyprice numeric(9,2) NOT NULL,
    isfeatured boolean DEFAULT false NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    appstoremonthlyproductid varchar(150) COLLATE ci,
    appstoreyearlyproductid varchar(150) COLLATE ci,
    playstoremonthlyproductid varchar(150) COLLATE ci,
    playstoreyearlyproductid varchar(150) COLLATE ci,
    CONSTRAINT pk_subscriptionplans PRIMARY KEY (planid)
);

CREATE TABLE dbo.subscriptionreceipts (
    receiptid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    planid uuid NOT NULL,
    store varchar(10) COLLATE ci NOT NULL,
    productid varchar(150) COLLATE ci NOT NULL,
    transactionid varchar(100) COLLATE ci NOT NULL,
    originaltransactionid varchar(100) COLLATE ci,
    purchasetoken text COLLATE ci,
    rawpayload text COLLATE ci,
    status varchar(20) COLLATE ci DEFAULT 'Active' NOT NULL,
    expiresatutc timestamp(3),
    autorenewing boolean DEFAULT false NOT NULL,
    verifiedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_subscriptionreceipts PRIMARY KEY (receiptid)
);

CREATE TABLE dbo.useractivedietplans (
    userid uuid NOT NULL,
    dietplanid uuid NOT NULL,
    activatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_useractivedietplans PRIMARY KEY (userid)
);

CREATE TABLE dbo.useractivesplits (
    userid uuid NOT NULL,
    splitid uuid NOT NULL,
    activatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    isautoassigned boolean DEFAULT false NOT NULL,
    CONSTRAINT pk_useractivesplits PRIMARY KEY (userid)
);

CREATE TABLE dbo.userauthidentities (
    authidentityid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    provider varchar(20) COLLATE ci NOT NULL,
    externalid varchar(256) COLLATE ci NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    refreshtokenciphertext bytea,
    CONSTRAINT pk_userauthidentities PRIMARY KEY (authidentityid)
);

CREATE TABLE dbo.userdevicetokens (
    devicetokenid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    platform varchar(20) COLLATE ci DEFAULT 'unknown' NOT NULL,
    pushtoken varchar(512) COLLATE ci NOT NULL,
    timezoneid varchar(100) COLLATE ci,
    isactive boolean DEFAULT true NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    lastseenatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_userdevicetokens PRIMARY KEY (devicetokenid)
);

CREATE TABLE dbo.usernotifications (
    notificationid uuid NOT NULL,
    userid uuid NOT NULL,
    category varchar(30) COLLATE ci NOT NULL,
    title varchar(120) COLLATE ci NOT NULL,
    body varchar(500) COLLATE ci NOT NULL,
    deeplink varchar(200) COLLATE ci,
    dedupekey varchar(120) COLLATE ci NOT NULL,
    status varchar(20) COLLATE ci DEFAULT 'Created' NOT NULL,
    providermessageid varchar(200) COLLATE ci,
    errormessage varchar(1000) COLLATE ci,
    scheduledlocalat timestamp(3),
    sentatutc timestamp(3),
    openedatutc timestamp(3),
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_usernotifications PRIMARY KEY (notificationid)
);

CREATE TABLE dbo.usernotificationstates (
    userid uuid NOT NULL,
    lastinteractionatutc timestamp(3),
    lastpushedatutc timestamp(3),
    lastmotivationatutc timestamp(3),
    lastcomebackatutc timestamp(3),
    pushedcount integer DEFAULT 0 NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_usernotificationstates PRIMARY KEY (userid)
);

CREATE TABLE dbo.usernutritiontargets (
    userid uuid NOT NULL,
    targetcalories_legacy smallint,
    targetproteing_legacy smallint,
    targetcarbsg_legacy smallint,
    targetfatsg_legacy smallint,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    targetcalories bytea,
    targetproteing bytea,
    targetcarbsg bytea,
    targetfatsg bytea,
    ismanualoverride boolean DEFAULT false NOT NULL,
    CONSTRAINT pk_usernutritiontargets PRIMARY KEY (userid)
);

CREATE TABLE dbo.userprofiles (
    userid uuid NOT NULL,
    gender_legacy varchar(10) COLLATE ci,
    ageyears_legacy smallint,
    heightcm_legacy numeric(5,1),
    weightkg_legacy numeric(5,1),
    goal_legacy varchar(20) COLLATE ci,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    gender bytea,
    ageyears bytea,
    heightcm bytea,
    weightkg bytea,
    goal bytea,
    trainingdaysperweek bytea,
    sessiondurationminutes bytea,
    trainingexperience bytea,
    equipmentaccess bytea,
    dailyactivitylevel bytea,
    CONSTRAINT pk_userprofiles PRIMARY KEY (userid)
);

CREATE TABLE dbo.users (
    userid uuid DEFAULT uuidv7() NOT NULL,
    deviceid varchar(200) COLLATE ci,
    displayname varchar(100) COLLATE ci,
    email varchar(256) COLLATE ci,
    passwordhash bytea,
    passwordsalt bytea,
    accounttier varchar(20) COLLATE ci DEFAULT 'Guest' NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    lastloginatutc timestamp(3),
    isactive boolean DEFAULT true NOT NULL,
    emailverifiedatutc timestamp(3),
    lastexportrequestedatutc timestamp(3),
    CONSTRAINT pk_users PRIMARY KEY (userid)
);

CREATE TABLE dbo.usersettings (
    userid uuid NOT NULL,
    targetwaterml integer DEFAULT 3500 NOT NULL,
    notificationsenabled boolean DEFAULT true NOT NULL,
    notificationlocaltime time(0) DEFAULT '18:00:00' NOT NULL,
    timezoneid varchar(100) COLLATE ci DEFAULT 'UTC' NOT NULL,
    updatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    weightunit varchar(3) COLLATE ci DEFAULT 'kg' NOT NULL,
    distanceunit varchar(3) COLLATE ci DEFAULT 'km' NOT NULL,
    resttimersoundenabled boolean DEFAULT true NOT NULL,
    barbellstandardkg numeric(5,2) DEFAULT 20.00 NOT NULL,
    appearancemode varchar(10) COLLATE ci DEFAULT 'Device' NOT NULL,
    avatarchoice varchar(10) COLLATE ci DEFAULT 'Male' NOT NULL,
    aidataconsentatutc timestamp(0),
    CONSTRAINT pk_usersettings PRIMARY KEY (userid)
);

CREATE TABLE dbo.usersubscriptions (
    userid uuid NOT NULL,
    planid uuid NOT NULL,
    billingcycle varchar(10) COLLATE ci NOT NULL,
    status varchar(20) COLLATE ci DEFAULT 'Active' NOT NULL,
    startedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    expiresatutc timestamp(3),
    latestreceiptid uuid,
    autorenewing boolean DEFAULT false NOT NULL,
    CONSTRAINT pk_usersubscriptions PRIMARY KEY (userid)
);

CREATE TABLE dbo.weeklyaiplandeliveries (
    deliveryid uuid NOT NULL,
    runid uuid NOT NULL,
    userid uuid NOT NULL,
    weekstartutc date NOT NULL,
    splitstatus varchar(20) COLLATE ci NOT NULL,
    dietstatus varchar(20) COLLATE ci NOT NULL,
    splitid uuid,
    dietplanid uuid,
    errormessage varchar(1000) COLLATE ci,
    generatedatutc timestamp(3),
    notifiedatutc timestamp(3),
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_weeklyaiplandeliveries PRIMARY KEY (deliveryid)
);

CREATE TABLE dbo.weeklyaiplanruns (
    runid uuid NOT NULL,
    weekstartutc date NOT NULL,
    status varchar(20) COLLATE ci DEFAULT 'Running' NOT NULL,
    usersconsidered integer DEFAULT 0 NOT NULL,
    plansgenerated integer DEFAULT 0 NOT NULL,
    notificationssent integer DEFAULT 0 NOT NULL,
    failures integer DEFAULT 0 NOT NULL,
    startedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    completedatutc timestamp(3),
    CONSTRAINT pk_weeklyaiplanruns PRIMARY KEY (runid)
);

CREATE TABLE dbo.weeklyanalyticsreports (
    reportid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    reportyear smallint NOT NULL,
    reportweek smallint NOT NULL,
    snapshotjson text COLLATE ci NOT NULL,
    resultjson text COLLATE ci NOT NULL,
    generatedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_weeklyanalyticsreports PRIMARY KEY (reportid)
);

CREATE TABLE dbo.workoutsessions (
    workoutsessionid uuid DEFAULT uuidv7() NOT NULL,
    userid uuid NOT NULL,
    splitdayid uuid,
    scheduleddateutc date NOT NULL,
    status varchar(20) COLLATE ci DEFAULT 'Scheduled' NOT NULL,
    startedatutc timestamp(3),
    completedatutc timestamp(3),
    durationminutes smallint,
    caloriesestimate smallint,
    rpescore numeric(3,1),
    tonnagekg numeric(10,2),
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    lastactivityatutc timestamp(3),
    firstsetcompletedatutc timestamp(3),
    CONSTRAINT pk_workoutsessions PRIMARY KEY (workoutsessionid)
);

CREATE TABLE dbo.workoutsetlogs (
    workoutsetlogid uuid DEFAULT uuidv7() NOT NULL,
    workoutsessionid uuid NOT NULL,
    userid uuid NOT NULL,
    exerciseid uuid NOT NULL,
    setnumber smallint NOT NULL,
    weightkg numeric(6,2) NOT NULL,
    reps smallint NOT NULL,
    completedatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    CONSTRAINT pk_workoutsetlogs PRIMARY KEY (workoutsetlogid)
);

CREATE TABLE dbo.workoutsplits (
    splitid uuid DEFAULT uuidv7() NOT NULL,
    name varchar(150) COLLATE ci NOT NULL,
    category varchar(50) COLLATE ci NOT NULL,
    level varchar(20) COLLATE ci DEFAULT 'Intermediate' NOT NULL,
    durationdays smallint NOT NULL,
    description varchar(500) COLLATE ci,
    heroimageurl varchar(500) COLLATE ci,
    issystemdefault boolean DEFAULT false NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdatutc timestamp(3) DEFAULT dbo.sysutcdatetime() NOT NULL,
    recommendedgoal varchar(20) COLLATE ci,
    owneradminuserid uuid,
    visibility varchar(20) COLLATE ci DEFAULT 'Public' NOT NULL,
    sourceurl varchar(500) COLLATE ci,
    sourceauthor varchar(300) COLLATE ci,
    fulldescription text COLLATE ci,
    popularityrank smallint,
    popularitywindow varchar(100) COLLATE ci,
    daysperweek smallint,
    programdurationweeks smallint,
    minsessionminutes smallint,
    maxsessionminutes smallint,
    equipmentrequired varchar(500) COLLATE ci,
    targetgender varchar(50) COLLATE ci,
    workouttypelabel varchar(100) COLLATE ci,
    sourcecategoriesjson text COLLATE ci,
    catalogrank integer,
    owneruserid uuid,
    isaigenerated boolean DEFAULT false NOT NULL,
    aikeptatutc timestamp(3),
    CONSTRAINT pk_workoutsplits PRIMARY KEY (splitid)
);
