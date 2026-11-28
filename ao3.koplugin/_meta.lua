return {
    -- KOReader ignores `name` (it reads `fullname`), but the KOReader App
    -- Store names an installed plugin from `name` and falls back to the
    -- folder. Without it the store shows "ao3" (from ao3.koplugin) and its
    -- overwrite guard compares that against the archive's "KO3", refusing
    -- updates. Keep this field even though KOReader logs it as deprecated.
    name = "KO3",
    fullname = "KO3",
    description = "Browse, search and read works from Archive of Our Own.",
    version = "1.9.2",
}
