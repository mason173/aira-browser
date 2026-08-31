# Browser Extension Sync Requires Aira Cloud As Primary

Superseded by ADR 0041 for the browser extension's provider scope. Its Aira Cloud eligibility rule remains in force whenever Aira Cloud is the extension's selected bookmark sync source.

Accepted: the Aira browser extension may read and write cross-system bookmark state only while Aira Cloud is the current Primary Sync Source and the account has Pro access. When Aira Cloud is a Backup Sync Source, extension sync is paused and the extension explains that Aira Cloud must be promoted before cross-system sync resumes. The backend must enforce the provider role rather than trusting UI state or login alone; otherwise extension writes would turn a write-only backup into a hidden second authority and could be overwritten by the next Aira backup.
