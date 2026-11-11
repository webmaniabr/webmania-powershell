# Changelog

## 0.1.0-alpha7

- README reescrito para a integração: requisitos, instalação, credenciais por variável de ambiente, exemplos de emissão, consulta e cancelamento de NF-e e NFS-e em homologação e a lista de métodos por produto. Os detalhes técnicos que estavam no README foram para `docs/INTEGRATION.md`, `docs/TESTING.md`, `docs/OPERATIONS.md` e `examples/homologacao/README.md`, sem mudança de conteúdo. Somente documentação.
- README (raiz e do módulo): o SDK passa a ser apresentado como disponível no repositório público do GitHub, com instalação a partir do clone (`git clone https://github.com/webmaniabr/webmania-powershell.git`); continua sem publicação em registro de pacotes. Somente documentação: código, contrato e DLLs incorporadas não mudam; o ZIP do módulo muda apenas no README incluído.
- O exemplo de homologação exige `WEBMANIA_LIVE_LEDGER` gravável nos escopos `nfe`, `nfse` e `all` (sai com 77, motivo `ledger`, antes de importar o módulo ou fazer requisições), para que um resultado desconhecido fique sempre registrado. Só o exemplo e os testes mudam; o ZIP do módulo não muda.
- `Webmania.Sdk` `0.1.0-preview.6` regenerado do contrato público atualizado (nova DLL fixada por SHA-256; nuspec, ponte e comandos inalterados): os totais da lista de classes de imposto (`tributos_federais`, `tributos_estaduais`) aceitam a string vazia que a API devolve para valor não definido; `situacao_tributaria` das classes de imposto tem 2 dígitos para IPI, PIS e COFINS e 2 a 3 dígitos para ICMS; `impostos.reducao` e `impostos.cp` da NFS-e aceitam string ou número.
- O exemplo de homologação trata `reprovado` (status da API 1.0 para NF-e recusada) como terminal.
- O exemplo de homologação exige `WEBMANIA_LIVE_ALLOWED_HOSTS` (sai com 77 antes de ler credenciais ou fazer requisições quando ela falta ou está vazia) e falha a execução quando a consulta depois do cancelamento não mostra `cancelado`.
- `examples/homologacao/run.sh` executa o exemplo `run.ps1` em ambientes POSIX (sem `WEBMANIA_LIVE=1`, sai com 77 sem importar o módulo).
- Depende de `Webmania.Sdk` `0.1.0-preview.6` (DLL, nuspec e licença fixados por SHA-256 em `module/Webmania/dependency.lock.json`); a ponte `Webmania.PowerShell.Runtime.dll` foi recompilada contra ela.
- A DLL `Webmania.Sdk` fixada (`c7a6f33f12d326ab56a0fd94c692eb93a818c6a8588e1097bfcdf16506e0e2b9`) inclui a correção de ZIP: marcadores ZIP64 por entrada resultam em `Unsupported` e um campo clássico de 32 bits acima do limite suportado é erro de protocolo, não falha de transferência. Nuspec, licença, ponte e comandos gerados permanecem inalterados.
- `scripts/Package.ps1` monta o pacote em um diretório temporário próprio e remove somente esse diretório: um subdiretório `stage` já existente no diretório de saída deixa de ser apagado, caminhos são tratados literalmente (sem curingas) e uma saída dentro de `module/Webmania` é recusada. O arquivo gerado é o mesmo.
- Contratos fixados por `contract_digest` (`371a499f74012bb6b41f23642869dee4954e8394dcba7642edc701aedb3dd59e`): 103 operações, 102 habilitadas. Os payloads de emissão da API 2.0 passam a usar os nomes `<Operação>Payload`.
- Novo comando `Receive-WebmaniaFiscalReportV2` e nova fábrica `New-WebmaniaReportCapabilityClient` para relatórios atuais; `Receive-WebmaniaFiscalReport` classifica CSV e XLSX rotulados `text/xml` pelos bytes.
- O módulo carrega DLLs, scripts e catálogo pelo caminho literal (`Add-Type -LiteralPath`, `Assembly.LoadFrom`, `Parser.ParseFile`), sem resolver curingas. Instale-o em um diretório sem `[`, `]`, `*` ou `?`: ao importar pelo manifesto, o PowerShell 7.6 interpreta esses caracteres no caminho do `RootModule`.
- `nfeDownloadIbsCbsEventXml` continua indisponível; a mensagem informa que nenhuma requisição foi enviada.
- Novo exemplo neutro de homologação em `examples/homologacao/run.ps1`, testado contra uma fixture loopback.
- O teste de entidade externa XML observa um listener real e mede as conexões recebidas; a CI fixa as actions por SHA e não persiste credenciais do checkout.

Prévia não publicada. Validação fiscal com a API real e demais plataformas permanecem pendentes.
