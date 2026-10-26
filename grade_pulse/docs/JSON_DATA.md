# Grade Pulse JSON data

## Canonical template

`assets/data/grade_pulse_data.json` is the **only** bundled sample/template. It is registered as a Flutter asset, is read-only at runtime, and is never loaded automatically; it is imported only when the user chooses *Import bundled sample JSON* and confirms.

The project previously contained a second, identical copy at the project root (`grade_pulse_data.json`). It was removed so there is one file to maintain. Compatibility: anything that still has that old copy can import it with *Import from JSON file*, because it is a plain version 1 file and version 1 stays fully supported.

## Format (schema version 4; versions 1, 2 and 3 are still accepted)

```jsonc
{
  "version": 4,                       // whole number; missing = treated as 1
  "meta": {                           // optional, written by Export
    "app": "grade_pulse",
    "exportedAt": "2026-10-18T13:05:00.000Z"
  },
  "terms": [ { "name": "…", "isDemo": false,
      "courses": [ { "code": "…", "title": "…", "units": 3,
          "assessments": [ { "title": "…", "category": "Quiz|Assignment|Exam|Laboratory|Project|Other",
                             "scoreAchieved": 95.0, "maxScore": 100.0 } ] } ] } ],
  "reminders": [ { "id": "…", "title": "…", "courseCode": "…",
      "category": "Assignment|Quiz|Exam|Project|Group Study|Personal|Other",
      "dateTime": "2026-10-19T14:30:00.000",   // ISO 8601 date and time
      "isCompleted": false, "isDemo": false,
      "description": "…", "priority": "Low|Medium|High", "groupId": "…" } ],
  "groups": [ { "id": "…", "name": "…", "members": ["…"], "notes": "",
      "courseCode": "…", "description": "…", "createdAt": "…", "isDemo": false } ],
  "profile": { "school": "…", "program": "…", "yearLevel": "…", "studentInfo": "…" },
  "settings": { "themeMode": "system|light|dark",
      "gpaScale": "Standard 4.0 GPA|Percentage %|TUP / PLM (1.0 - 5.0)",
      "calcCurrent": "", "calcWeight": "", "calcRemaining": "", "calcTarget": "",
      "targetPercent": 90,                       // optional goal (1-100)
      "gradeBands": {                            // optional, only scales the user edited
        "TUP / PLM (1.0 - 5.0)": [ { "min": 95, "grade": 1.0 }, { "min": 0, "grade": 5.0 } ] } }
}
```

Required: `terms[].name`, `courses[].code`, `assessments[].title/scoreAchieved/maxScore` (score ≥ 0, max > 0; a score above max is kept but flagged), `reminders[].id/title/dateTime`, `groups[].id/name`. Everything else is optional and gets a safe default (units 3, category "Assignment", empty lists/strings, priority "Medium", system theme, …). A reminder with `groupId` must reference a group in the same user data file. Group tasks and sessions are stored as reminders linked to the group, rather than duplicated inside the group object. Reminder and group ids must be unique within a file.

Not stored in these files, ever: passwords, hashes, salts, session data, e-mail address, or authentication identity. The optional `profile` object contains only non-sensitive academic metadata (school, program, year level, and optional student information).

## Loading rules (`lib/services/data_codec.dart`)

* All validation happens before any model is built; one invalid value rejects the whole file with a list of exact locations (e.g. `terms[0].courses[1].assessments[2].maxScore`). Nothing is partially imported.
* Unknown fields are not dropped silently: they are listed as notes in the import preview. An unknown reminder category, theme or GPA scale falls back to the default and is also listed.
* Per-user storage (`StorageService.load`) uses the same codec, so old records are migrated on load; a record that cannot be read is left untouched.

## Changing the schema later

1. Bump `UserData.schemaVersion` in `models.dart`.
2. Register `UserDataCodec.migrations[<old version>] = (json) => …` returning the map upgraded by one version.
3. Add a test (see the `schema migrations` group in `test/data_codec_test.dart`).

Files with a version newer than the app supports are refused with an "update the app" message.

## Schema history

| Version | Changes |
|---|---|
| 1 | `version`, `terms`, `reminders`, `groups`, `settings` (`themeMode`, `gpaScale`, `calcCurrent`, `calcWeight`, `calcTarget`). |
| 2 | Adds `assessments[].category`, `settings.calcRemaining`, `settings.targetPercent`, `settings.gradeBands`. |
| 3 | Adds reminder `description`, `priority`, optional `groupId`; adds group `courseCode`, `description`, and optional `createdAt`. |
| 4 | Adds optional non-sensitive `profile` metadata (`school`, `program`, `yearLevel`, `studentInfo`). Authentication identity and credentials remain outside JSON. |

**Migrations 1 → 2 → 3 → 4** run automatically on import and when saved data is loaded. The 2 → 3 migration adds safe defaults to older reminders and study groups while preserving existing IDs, dates, completion states, and records. Every assessment without a category gets one guessed from its title (Quiz, Laboratory, Project, Exam, Assignment, else Other). All other values, including the version 1 settings keys, are kept; the new settings take their defaults (no target, built-in grade tables). The bundled sample is still a version 1 file, so importing it exercises this migration.

## What is *not* stored

Averages, GPA, term and cumulative results, trends, strongest/lowest subjects, target progress and "needs attention" items are **calculated on demand** from terms, subjects and assessments (`lib/services/grade_math.dart`, `lib/services/analytics.dart`). They are never written to JSON, so they cannot disagree with the grades, and an exported-then-imported file gives identical results (covered by `test/analytics_test.dart`).

## Grade conversion tables

The 4.0 GPA and TUP / PLM tables are **generic defaults, not official rules** (no official TUP table could be verified). The user can edit them under Settings → Grading → Grade conversion tables; edited tables are saved in `settings.gradeBands` and used everywhere. The active scale and whether its table is the default or edited is always shown in the calculator, in Insights and in Settings.
