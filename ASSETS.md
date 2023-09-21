# Asset inventory

The following information assets are required to run https://catircservices.org:

- Source control repository `whitequark/catircservices.org`
  - Provider: [GitHub](https://github.com)
  - Owner: Catherine
  - Operators: Catherine, Charlotte
  - Link: https://github.com/whitequark/catircservices.org
- Matrix channel `#admin:catircservices.org`
  - Provider: [Matrix.org](https://matrix.org)
  - Owners/operators: Catherine, Charlotte
  - Link: https://matrix.to/#/#admin:catircservices.org
- Domain name `catircservices.org`
  - Provider: [Gandi](https://gandi.net)
  - Owner: Catherine
  - Operators: Catherine
  - Link: https://admin.gandi.net/domain/1c9d73d2-a93a-11ed-9269-00163e816020/catircservices.org/overview
  - Additional services provided:
    - DNS zone:
      ```zone
      @ 10800 IN MX 10 spool.mail.gandi.net.
      @ 10800 IN MX 50 fb.mail.gandi.net.
      @ 10800 IN TXT "v=spf1 include:_mailcust.gandi.net ?all"
      @ 600 IN A 5.75.226.159
      @ 600 IN AAAA 2a01:4f8:c012:5b7::1
      staging 600 IN A 128.140.91.194
      staging 600 IN AAAA 2a01:4f8:c012:907c::1
      ```
    - Email `admin@catircservices.org` redirecting to `whitequark@gmail.com`
- Cloud server `5.75.226.159`, `2a01:4f8:c012:5b7::/64` (DNS `catircservices.org`)
  - Provider: [Hetzner](https://www.hetzner.com/cloud)
  - Owner: Catherine
  - Operators: Catherine, Charlotte
  - Link: https://console.hetzner.cloud/projects/2447970/servers/34720043/overview
  - Location: fsn1-dc14
- Cloud server `128.140.91.194`, `2a01:4f8:c012:907c::/64` (DNS `staging.catircservices.org`)
  - Provider: [Hetzner](https://www.hetzner.com/cloud)
  - Owner: Catherine
  - Operators: Catherine, Charlotte
  - Link: https://console.hetzner.cloud/projects/2447970/servers/34841806/overview
  - Location: fsn1-dc14
- IRC nickname `_catircservices` (production)
  - Provider: [Libera](https://libera.chat)
  - Owner: Catherine
  - Operators: Catherine, Charlotte
- IRC nickname `_catircstaging` (staging)
  - Provider: [Libera](https://libera.chat)
  - Owner: n/a (not registered)
- Discord application `1135424862811324416` (production)
  - Provider: [Discord](https://discord.com)
  - Owner: Catherine
  - Operators: Catherine
  - Link: https://discord.com/developers/applications/1135424862811324416/information
- Discord application `1135426125452025937` (staging)
  - Provider: [Discord](https://discord.com)
  - Owner: Catherine
  - Operators: Catherine
  - Link: https://discord.com/developers/applications/1135426125452025937/information
