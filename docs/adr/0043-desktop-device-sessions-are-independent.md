# Desktop Device Sessions Are Independent

Accepted: each browser-extension installation owns an independent, long-lived Desktop Device Session, so pairing a new computer never replaces another computer's credential. Until the App adds device selection, Phone Page Push broadcasts one independent delivery to every device online at enqueue time; offline devices receive no historical delivery, legacy single-device credentials migrate without forced pairing, and explicit logout revokes only the current device.

Online eligibility comes from recent authenticated Phone Page Push polling or acknowledgement, not from pairing or membership refresh alone. A delivery expires after two minutes so a device that stops polling does not receive an old webpage after it returns.
