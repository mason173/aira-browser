# Huawei Space Uses Aira-Generated Source IDs

Accepted: Huawei Space Sync will use an Aira-generated stable source id for each install or sync client instead of relying on Huawei device names, system device IDs, or user-editable nicknames. The source id is non-secret, distinct from account identity, and is recorded with commits, tombstones, and sync metadata so conflict handling and deletion safety do not depend on mutable or unavailable platform identifiers.
