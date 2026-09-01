# Phone Page Push Is Independent Of Bookmark Sync

Accepted: Phone Page Push and Bookmark Sync are separate product flows, but Page Push uses the active service Provider.
When the active Provider is Personal Server, the HarmonyOS App authenticates with its paired phone credential and the
paired Aira-sync installations receive the page without Aira Account or Pro. When the active Provider is Aira Cloud, the
existing verified Huawei Account and Pro boundary remains. WebDAV and Huawei Cloud Space do not transport Page Push.

Changing the active Provider does not mutate bookmark snapshots, baselines, CAS state, or conflict handling. A valid
pushed webpage immediately opens in a new active desktop tab and is acknowledged through the lease flow, without an
inbox or deferred-delivery UI. Personal Server creates one short-lived task for every paired desktop that is online at
enqueue time; offline devices receive no historical delivery.
