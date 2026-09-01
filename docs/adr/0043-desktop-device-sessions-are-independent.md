# Desktop Device Sessions Are Independent

Accepted: each browser-extension installation owns an independent, long-lived Desktop Device Session, so pairing a new computer never replaces another computer's credential. Until the App adds device selection, Phone Page Push broadcasts one independent delivery to every device online at enqueue time; offline devices receive no historical delivery, legacy single-device credentials migrate without forced pairing, and explicit logout revokes only the current device.

Online eligibility comes from recent authenticated Phone Page Push polling or acknowledgement, not from pairing or membership refresh alone. A delivery expires after two minutes so a device that stops polling does not receive an old webpage after it returns.

Personal Server uses the same independence rule with its own paired-device credentials. Pairing an Aira-sync installation
creates a `desktop` device credential; pairing the HarmonyOS App creates a `phone` device credential. These credentials
belong only to that Personal Server instance and never reuse an Official Desktop Device Session, Huawei token, Aira UID,
or Pro entitlement. Revoking one paired device removes only that installation's access, while other paired devices keep
working.
