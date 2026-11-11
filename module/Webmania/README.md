# Webmania SDK para PowerShell

Integração de **Emissor Fiscal e Monitor Fiscal** em aplicações de servidor. O Emissor abrange NF-e/NFC-e na API1 e NFS-e, CT-e/CT-e OS, MDF-e, NFCom e DC-e na API2, com arquivos, eventos e as três operações gerenciais B2B públicas da API1. O Monitor mantém apenas as famílias de documentos e capacidades do seu contrato documentado.

Disponível no repositório público [github.com/webmaniabr/webmania-powershell](https://github.com/webmaniabr/webmania-powershell), com instalação a partir do clone (veja a seção Instalação). Ainda não há publicação em registro de pacotes; os nomes e versões abaixo identificam os pacotes gerados a partir desta fonte. Regras do provedor, aceitação fiscal real e plataformas adicionais permanecem com limitações explícitas.

## Requisitos

PowerShell 7.6+ sobre .NET 10. Perfil atual: PowerShell 7.6.8/.NET 10.0.14 em Linux arm64. Windows PowerShell 5.1, Windows e macOS não estão qualificados. O módulo verifica a identidade da dependência .NET incorporada e conflitos de assembly.

## Instalação

Clone o repositório público, gere o ZIP do módulo a partir do clone com `scripts/Package.ps1` e importe seu manifesto:

```powershell
git clone https://github.com/webmaniabr/webmania-powershell.git
./webmania-powershell/scripts/Package.ps1 -OutputDirectory ./pacote
Expand-Archive ./pacote/Webmania.0.1.0-alpha7.zip -DestinationPath ./sdk
Import-Module ./sdk/Webmania/Webmania.psd1
Get-WebmaniaOperation | Select-Object Id, Scope, Enabled, ContractStatus
```

O módulo também pode ser carregado diretamente de `module/Webmania` no clone, como faz o exemplo de homologação. Mantenha todo o módulo junto com a dependência incorporada. Não exige compilador, restore NuGet ou gerador. O próprio módulo carrega DLLs, scripts e catálogo pelo caminho literal do seu diretório. Instale-o em um diretório sem `[`, `]`, `*` ou `?`: ao importar pelo manifesto, o PowerShell 7.6 interpreta esses caracteres no caminho do `RootModule` como curinga.

## Primeira consulta

Configure somente a credencial do serviço escolhido, por instância, a partir de ambiente privado ou cofre de segredos. O exemplo não emite nem cancela documentos. Execute consultas apenas com conta e ambiente autorizados; uma origem de fixture controlada deve ser configurada explicitamente pela API do cliente.

```powershell
$token = Read-Host 'Monitor bearer token' -AsSecureString
$client = New-WebmaniaMonitorClient -Bearer $token
try {
    $p = [Webmania.MonitorListCompaniesParameters]::new()
    $p.PerPage = New-WebmaniaOptional -Type ([Webmania.JsonNumber]) `
        -Value (New-WebmaniaJsonNumber -Text '10')
    $response = Get-WebmaniaMonitorCompanies -Client $client -Parameters $p
    $response.StatusCode
} finally { $client.Dispose() }
```

A construção do cliente não comprova habilitação da conta. Respostas de sucesso e conversões explícitas para JSON podem conter dados fiscais, credenciais novas ou URLs privadas. Exponha apenas os campos necessários à aplicação.

## Integração e limites

Os comandos recebem o DTO exato em `-Parameters`, o cliente do escopo em `-Client`, `-CancellationToken` opcional e `-AsTask`. Sem `-AsTask`, a chamada espera o resultado tipado. A interrupção nativa do pipeline cancela a chamada em andamento e espera sua limpeza; uma Task devolvida continua pertencendo ao chamador, que deve manter token e cliente vivos até terminar. Descarte o cliente com `Dispose()`.

Campos DTO começam omitidos. Use `New-WebmaniaOptional -Type ([T]) -Null` para null explícito e `New-WebmaniaJsonNumber -Text '123.4500'` para números exatos. Zero, false, unions e extensões preservam seus tipos. Construa DTOs com `::new()`; hashtables sem tipo não são argumentos válidos de operação. Não passe números precisos por ponto flutuante.

`Read-WebmaniaMonitorCompanyBatch`, `Read-WebmaniaMonitorCompanyMunicipalityBatch` e `Read-WebmaniaMonitorReportBatch` aceitam limites de itens/páginas e continuação tipada em memória. Retome com os mesmos filtros e tamanho de página. A continuação não pode ser restaurada do JSON diagnóstico. `Wait-WebmaniaFiscalReport` e `Wait-WebmaniaMonitorImport` usam PollOptions finitas e intervalo mínimo de cinco segundos; a importação inicial não é repetida.

Arquivos mantêm `Representation`, `Readiness` e `IsFile`. PDF/ZIP protegidos não são texto aberto; HTML, JSON pendente e redirect não são arquivos prontos. `Save-WebmaniaFile -InputObject` ou um pipeline normal exige FileResult validado; sobrescrever exige `-Force`. Não use o parâmetro interno PipelineInput.

`WebmaniaException` informa `Kind`, `StatusCode`, `OutcomeUncertain` e `RecoveryAdvice`; `SafeReference` pode ser nula. Acesso deliberado usa `SafeReference?.Reveal()`. `WebmaniaCancellationException` mantém o cancelamento nativo .NET e seu contexto tipado. Não exporte valores privados de ErrorRecords.

## Ambiente, URL base e relatórios

As fábricas aceitam `-Options` com um `[Webmania.WebmaniaClientOptions]`. `ServiceEndpoint` substitui a base HTTPS do contrato por uma base explícita, com prefixo de caminho opcional, sem usuário, query, fragmento ou segmentos `.`/`..`; `LoopbackTestEndpoint` aceita apenas a origem de uma fixture local. O módulo não lê ambiente por conta própria. Quando o processo não tem um host `dotnet` ao lado do runtime, configure `DnsHelperHost` com o caminho absoluto de um host .NET para o resolvedor de nomes.

`Receive-WebmaniaFiscalReport` atende relatórios legados: CSV e XLSX rotulados `text/xml` são identificados pelos bytes (assinatura ZIP = XLSX; qualquer outro corpo = CSV devolvido byte a byte, inclusive Latin-1); XML, HTML ou JSON nesse download é recusado e nenhum outro comando ganha essa tolerância. Relatórios atuais usam `Receive-WebmaniaFiscalReportV2` com `New-WebmaniaReportCapabilityClient` e a base da API 2.0; um JSON com `error`, mesmo em HTTP 200, é falha.

## Credenciais e resultado fiscal

Credenciais da empresa API1, revenda API1, Bearer do emissor API2 e Bearer Monitor pertencem a escopos diferentes. Arquivos exigem a modalidade de acesso documentada. Uma falha não autoriza trocar automaticamente o modo ou a credencial. Mantenha segredos no servidor.

O catálogo contém 103 operações, 102 habilitadas. `nfeDownloadIbsCbsEventXml` não está disponível nesta versão do SDK: o comando falha com `Kind` igual a `capability_unavailable` e nenhuma requisição é enviada. Condições fiscais, municipais, de cadastro e de provedor continuam sujeitas ao contrato e ao serviço. Validação local, cálculo ou prévia não comprovam autorização fiscal.

Não há retry automático de operação nem seguimento automático de redirects. Depois de possível envio de uma operação com efeito, uma falha pode indicar resultado desconhecido. Preserve o seletor original com segurança, consulte a tentativa anterior e decida explicitamente como prosseguir. Uma referência protegida exige acesso deliberado e pode estar ausente; não é uma chave de idempotência.

## Arquivos e processamento

Verifique tipo de resultado, status e representação antes de consumir bytes. JSON pendente, HTML e redirect não comprovam PDF pronto. Proteção de PDF/ZIP é distinta da autorização de download; não há descriptografia automática nem confirmação de autenticidade fiscal. O reconhecimento de formatos cobre somente o perfil documentado desta implementação. Uma Location revelada continua privada e exige decisão explícita de origem e autenticação para outra transferência.

Paginação e espera são optativas e limitadas quando disponíveis. Um estado futuro ou desconhecido não significa conclusão. Não repita emissão, cancelamento ou importação inicial como se fossem consultas de processamento.

Para migrar uma integração anterior, remapeie métodos, modelos e escopos de credencial pela referência desta versão. Não há promessa de substituição automática de outro SDK; compare também o changelog quando disponível.

## Referências

[commands.json](commands.json) · [docs/CREDENTIALS.md](../../docs/CREDENTIALS.md) · [examples](../../examples) · [Documentação Webmania](https://webmania.com.br/docs/) · [LICENSE](LICENSE) · [Termos de Uso](https://webmania.com.br/termos-de-uso/)

Licença proprietária Webmania. Dependências de terceiros mantêm suas licenças e avisos de atribuição.
