USE SilenDb;
GO

-- Existing installations already have these prompt rows. Add the same
-- preview-copy rules enforced by WeeklyPlanGenerationService so prompt tuning
-- in the database and the strict runtime JSON schema remain aligned.
UPDATE dbo.AiPromptTemplates
SET
    SystemPrompt = SystemPrompt +
        N' Give every generated split a concise preview title and a specific one- or two-sentence ' +
        N'description of its structure and why it fits the supplied evidence. Avoid generic AI labels ' +
        N'and unsupported claims.',
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE TemplateKey = N'WeeklySplitGeneration'
  AND SystemPrompt NOT LIKE N'%concise preview title%';
GO

UPDATE dbo.AiPromptTemplates
SET
    SystemPrompt = SystemPrompt +
        N' Give every generated diet plan a concise, appetizing preview title and a one- or two-sentence ' +
        N'description of its nutrition strategy and variety. Only mention ingredients or benefits supported ' +
        N'by the supplied meal catalog.',
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE TemplateKey = N'WeeklyDietGeneration'
  AND SystemPrompt NOT LIKE N'%appetizing preview title%';
GO

-- AnalyticsService also appends these rules at runtime. Persisting them here
-- keeps admin-visible prompt templates honest about the structured response
-- quality expected by the monthly and weekly recap previews.
UPDATE dbo.AiPromptTemplates
SET
    SystemPrompt = SystemPrompt +
        N' Each strength must name its supporting metric or logged behavior. Each improvement must identify ' +
        N'one specific area and one realistic next action. Do not repeat the same observation across fields.',
    UpdatedAtUtc = SYSUTCDATETIME()
WHERE TemplateKey IN (N'MonthlyAnalytics', N'WeeklyAnalytics')
  AND SystemPrompt NOT LIKE N'%supporting metric or logged behavior%';
GO
