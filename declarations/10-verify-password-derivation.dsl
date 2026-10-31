capability verify-password-derivation
intent: Verify the declared password derivation against an independent Argon2id test vector: the vector step builds a throwaway password and salt, the derive port (sfx-identity-login-derive) derives the tag, and the answer is MATCHES when the tag equals the expected base64, or MISMATCH with the tag.
outcome: verify-password-derivation-result.v1 MATCHES, or MISMATCH with the tag
inquiry: Does the declared derivation produce the expected tag?
input contract verify-password-derivation-request.v1 {"type":"object","additionalProperties":false}
output contract verify-password-derivation-result.v1 {"type":"object","additionalProperties":true,"required":["status"],"properties":{"status":{"enum":["MATCHES","MISMATCH"]},"tag":{"type":"string"}}}
cli display outcome as json
scenario verify-password-derivation root terminal
given: the throwaway vector and the derive port
when: the vector is built and the derive port derives the tag
then: the outcome is MATCHES when the tag equals the expected value
operation verify-password-derivation.vector kind invoke-port port verify-password-derivation-vector
operation verify-password-derivation.derive kind invoke-port port verify-password-derivation-derive
operation verify-password-derivation.answer kind invoke-port port verify-password-derivation-answer
platform bind verify-password-derivation-vector
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"object","fields":{"password":{"op":"literal","value":"sfx login check OpYAnFIY"},"salt":{"op":"literal","value":"XzV3zhcHfl3N2ArfiSCREw=="}}}}
platform bind verify-password-derivation-derive
platform: sfx-identity-login-derive-port.v1
config: {"providerId":"sfx-identity-login-derive","dependency":{"objectKind":"DEPENDENCY","namespace":"sidefx:dependencies","id":"sfx-identity-login"}}
platform bind verify-password-derivation-answer
platform: sda-authority-transformation-port.v1
config: {"expression":{"op":"if","when":{"op":"equals","left":{"op":"path","path":"tag"},"right":{"op":"literal","value":"9F6e2oJcKYMjMt/RRwS4V6QM3w8LNxmbOYuI/7A/oXY="}},"then":{"op":"object","fields":{"status":{"op":"literal","value":"MATCHES"}}},"else":{"op":"object","fields":{"status":{"op":"literal","value":"MISMATCH"},"tag":{"op":"path","path":"tag"}}}}}
