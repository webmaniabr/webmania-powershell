# Credential scopes

Each factory returns its own disposable `WebmaniaClient`. Four-value factories accept `-ConsumerKey`, `-ConsumerSecret`, `-AccessToken`, `-AccessTokenSecret`; all values are `SecureString`. Bearer factories accept `-Bearer`; token factories accept `-Token`. Factories also accept a typed `WebmaniaClientOptions`.

| Factory suffix after `New-Webmania` | Scope and usage |
| --- | --- |
| `CompanyClient` | API1 fiscal company four headers |
| `IssuerClient` | API2 issuance/read bearer |
| `MonitorClient` | Monitor bearer |
| `ResellerClient` | API1 B2B four headers |
| `Api1FilesCompanyClient` | API1 file four headers |
| `Api1FilesDocumentTokenClient` | API1 file document token, encoded once in query |
| `Api1ReportCapabilityClient` | Explicit API1 report capability from the request UUID |
| `ReportCapabilityClient` | Report capability for the current report download (`Receive-WebmaniaFiscalReportV2`); no credential header is sent |
| `Api2FilesCompanyBearerClient` | API2 file company bearer |
| `Api2FilesDocumentTokenClient` | Document token, only where the pinned contract allows it |
| `Api2FilesAnonymousClient` | Anonymous, only where the pinned contract allows it |

The SDK prevents substituting these scopes. MDF-e files require company bearer; an anonymous or document-token client does not bypass that requirement. Report UUIDs and file URLs can be capability secrets; retain them securely and use their explicit protected reveal APIs only when necessary.

Production `ServiceEndpoint` accepts an explicit HTTPS base under the SDK's validation. `DnsHelperHost` names the absolute path of a .NET host for the name resolver when the runtime has no `dotnet` host next to it. `LoopbackTestEndpoint` and `LoopbackTestRootCertificate` are explicit controlled-test options; the latter preserves hostname validation. No option disables TLS validation, selects proxy credentials, reads environment tokens or adds a retry policy.
