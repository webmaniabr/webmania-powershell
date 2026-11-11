<p align="center"><img src=".github/assets/webmania-logo.png" alt="Webmania" width="320"></p>

# Webmania SDK para PowerShell

Através do emissor fiscal da Webmania®, você conta com a emissão e o arquivamento dos seus documentos fiscais, cálculo automático de impostos, geração do DANFE para impressão e envio automático de e-mails para os clientes. Com este SDK, o seu sistema em PowerShell se integra à nossa REST API para emitir, consultar e cancelar NF-e, NFC-e, NFS-e, CT-e, MDF-e, NFCom e DC-e, baixar XML e PDF dos documentos e usar o Monitor Fiscal.

- Emissor de Nota Fiscal Webmania®: [Saiba mais](https://webmania.com.br/nota-fiscal-eletronica/)
- Documentação da REST API: [Visualizar](https://webmania.com.br/docs/)
- Índice da documentação para assistentes de IA: [llms.txt](https://webmania.com.br/docs/llms.txt)

## Requisitos

- Contrate um dos planos de Nota Fiscal Eletrônica da Webmania®: [Assine agora mesmo](https://webmania.com.br/nota-fiscal-eletronica/#plans-section).
- PowerShell 7.6 ou superior, sobre .NET 10. O módulo já inclui a biblioteca .NET do SDK.
- Credenciais de acesso da sua empresa, disponíveis no [Painel de Controle](https://webmania.com.br/painel/).

## Instalação

O SDK é distribuído pelo repositório [github.com/webmaniabr/webmania-powershell](https://github.com/webmaniabr/webmania-powershell) e ainda não está publicado na PowerShell Gallery. Clone o repositório, gere o ZIP do módulo e importe o manifesto:

```powershell
git clone https://github.com/webmaniabr/webmania-powershell.git
./webmania-powershell/scripts/Package.ps1 -OutputDirectory ./pacote
Expand-Archive ./pacote/Webmania.0.1.0-alpha7.zip -DestinationPath ./sdk
Import-Module ./sdk/Webmania/Webmania.psd1
```

O módulo também pode ser carregado diretamente de `module/Webmania` no clone. Para listar todas as operações disponíveis, use `Get-WebmaniaOperation`.

## Credenciais

Cada serviço usa a sua própria credencial. Guarde-as em variáveis de ambiente (ou em um cofre de segredos) no servidor e nunca as escreva no código-fonte:

| Variável de ambiente | Uso |
|---|---|
| `WEBMANIA_CONSUMER_KEY`, `WEBMANIA_CONSUMER_SECRET`, `WEBMANIA_ACCESS_TOKEN`, `WEBMANIA_ACCESS_TOKEN_SECRET` | NF-e e NFC-e (`New-WebmaniaCompanyClient`) e arquivos da NF-e (`New-WebmaniaApi1FilesCompanyClient`) |
| `WEBMANIA_ISSUER_TOKEN` | NFS-e, CT-e, MDF-e, NFCom e DC-e (`New-WebmaniaIssuerClient`) e seus arquivos (`New-WebmaniaApi2FilesCompanyBearerClient`) |
| `WEBMANIA_MONITOR_TOKEN` | Monitor Fiscal (`New-WebmaniaMonitorClient`) |

```powershell
function Segredo([string]$Nome) { ConvertTo-SecureString -String ([Environment]::GetEnvironmentVariable($Nome)) -AsPlainText -Force }

$empresa = @{
    ConsumerKey = Segredo 'WEBMANIA_CONSUMER_KEY'; ConsumerSecret = Segredo 'WEBMANIA_CONSUMER_SECRET'
    AccessToken = Segredo 'WEBMANIA_ACCESS_TOKEN'; AccessTokenSecret = Segredo 'WEBMANIA_ACCESS_TOKEN_SECRET'
}
$nfe = New-WebmaniaCompanyClient @empresa                                   # NF-e e NFC-e
$emissor = New-WebmaniaIssuerClient -Bearer (Segredo 'WEBMANIA_ISSUER_TOKEN') # NFS-e, CT-e, MDF-e, NFCom e DC-e

# Monta os parâmetros tipados de uma operação a partir de um objeto.
function Parametros([type]$Tipo, $Valor) {
    [Text.Json.JsonSerializer]::Deserialize(($Valor | ConvertTo-Json -Compress -Depth 10), $Tipo, [Webmania.WebmaniaJson]::Options)
}
```

Cada cliente atende o serviço da credencial que recebeu; chame `Dispose()` ao terminar. Os comandos devolvem a resposta com `StatusCode` (status HTTP) e `Json` (o JSON da resposta).

## Utilização

Os exemplos abaixo usam o ambiente de **homologação** (`ambiente` 2), em que os documentos não têm validade fiscal. Para emitir em produção, envie `ambiente` 1. Informe valores decimais como texto (`"44.90"`) para manter a precisão.

### Status do SEFAZ e certificado A1

```powershell
$sefaz = Get-WebmaniaNfeSefazStatus -Client $nfe -Parameters ([Webmania.NfeGetSefazStatusParameters]::new())
$sefaz.Json.GetProperty('status').GetString()                # online ou offline

$certificado = Get-WebmaniaNfeCertificateValidity -Client $nfe -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new())
$certificado.Json.GetProperty('expiration').GetInt32()       # dias até o vencimento do certificado A1
```

### Emitir NF-e

Para emitir uma NF-e, use `Submit-WebmaniaNfeDocument` com o JSON da nota no campo `body`. O mesmo comando emite NFC-e com `"modelo": 2`.

```powershell
$dados = @'
{
  "operacao": 1,
  "natureza_operacao": "Venda de produção do estabelecimento",
  "modelo": 1,
  "finalidade": 1,
  "ambiente": 2,
  "cliente": {
    "cpf": "000.000.000-00", "nome_completo": "Nome do Cliente",
    "endereco": "Av. Brg. Faria Lima", "numero": "1000", "bairro": "Itaim Bibi",
    "cidade": "São Paulo", "uf": "SP", "cep": "00000-000", "email": "nome@email.com"
  },
  "produtos": [{
    "nome": "Nome do produto", "codigo": "nome-do-produto", "ncm": "6109.10.00",
    "quantidade": "1", "unidade": "UN", "origem": 0,
    "subtotal": "44.90", "total": "44.90", "classe_imposto": "REF1000"
  }],
  "pedido": {"presenca": 2, "modalidade_frete": 9, "pagamento": 0, "forma_pagamento": "01", "total": "44.90"}
}
'@ | ConvertFrom-Json

$emissao = Submit-WebmaniaNfeDocument -Client $nfe -Parameters (Parametros ([Webmania.NfeIssueDocumentParameters]) @{ body = $dados })
$nota = $emissao.Json
$uuid = $nota.GetProperty('uuid').GetString()   # identificador único da nota fiscal
$nota.GetProperty('status').GetString()         # aprovado, reprovado, processamento...
$nota.ToString()                                # chave, xml (URL do XML), danfe (URL do DANFE) e motivo (retorno do SEFAZ)
```

Somente o status `aprovado` indica uma nota autorizada. Quando o retorno for `processamento`, consulte a nota alguns segundos depois.

### Consultar NF-e

```powershell
$consulta = Get-WebmaniaNfeDocument -Client $nfe -Parameters (Parametros ([Webmania.NfeGetDocumentParameters]) @{ uuid = $uuid })
$consulta.Json.GetProperty('status').GetString()
```

A consulta também aceita a chave de acesso (`chave`).

### Cancelar NF-e

```powershell
$cancelamento = Stop-WebmaniaNfeDocument -Client $nfe -Parameters (Parametros ([Webmania.NfeCancelDocumentParameters]) @{
    body = @{ uuid = $uuid; motivo = 'Cancelamento por erro no pedido.' }   # motivo: mínimo de 15 caracteres
})
$cancelamento.Json.GetProperty('status').GetString()
```

### Baixar o DANFE e o XML

Os arquivos da NF-e usam um cliente com a credencial de arquivos da empresa:

```powershell
$arquivos = New-WebmaniaApi1FilesCompanyClient @empresa

$danfe = Receive-WebmaniaNfeDanfe -Client $arquivos -Parameters (Parametros ([Webmania.NfeDownloadDanfeParameters]) @{ identifier = $uuid })
if ($danfe.IsFile) { [IO.File]::WriteAllBytes((Join-Path $PWD 'danfe.pdf'), $danfe.Bytes.ToArray()) }

$xml = Receive-WebmaniaNfeXml -Client $arquivos -Parameters (Parametros ([Webmania.NfeDownloadXmlParameters]) @{ identifier = $uuid })
if ($xml.IsFile) { [IO.File]::WriteAllBytes((Join-Path $PWD 'nfe.xml'), $xml.Bytes.ToArray()) }
```

Confira `IsFile` antes de gravar: a resposta pode indicar que o arquivo ainda está sendo gerado.

### Emitir, consultar e cancelar NFS-e

A NFS-e é emitida a partir de um ou mais RPS com `Submit-WebmaniaEmitterNfse`:

```powershell
$rps = @'
{
  "ambiente": 2,
  "rps": [{
    "servico": {
      "valor_servicos": "15.00",
      "discriminacao": "Prestação de serviço referente ao mês 10/2026",
      "classe_imposto": "REF000000"
    },
    "tomador": {"cpf": "000.000.000-00", "nome_completo": "Nome do tomador"}
  }]
}
'@ | ConvertFrom-Json
$nfse = Submit-WebmaniaEmitterNfse -Client $emissor -Parameters (Parametros ([Webmania.EmitterIssueNfseParameters]) @{ body = $rps })
$uuidNfse = $nfse.Json.GetProperty('uuid').GetString()
$nfse.Json.GetProperty('status').GetString()

$consultaNfse = Get-WebmaniaEmitterNfse -Client $emissor -Parameters (Parametros ([Webmania.EmitterGetNfseParameters]) @{ identifier = $uuidNfse })
$consultaNfse.Json.GetProperty('status').GetString()

$canceladaNfse = Stop-WebmaniaEmitterNfse -Client $emissor -Parameters (Parametros ([Webmania.EmitterCancelNfseParameters]) @{
    body = @{
        uuid = $uuidNfse
        motivo = '1'                                              # código do motivo (veja a documentação da NFS-e)
        justificativa = 'Serviço cancelado a pedido do tomador.'  # mínimo de 15 caracteres
    }
})
$canceladaNfse.Json.GetProperty('status').GetString()
```

### Tratamento de erros

As falhas chegam como `Webmania.WebmaniaException`:

```powershell
try {
    Submit-WebmaniaNfeDocument -Client $nfe -Parameters (Parametros ([Webmania.NfeIssueDocumentParameters]) @{ body = $dados })
} catch {
    $erro = $_.Exception
    if ($erro -is [Webmania.WebmaniaException]) {
        $erro.Kind          # validation (dados recusados antes do envio), business (recusa da API ou do SEFAZ), http, timeout...
        $erro.StatusCode    # status HTTP, quando houver
        $erro.Message       # mensagem, com dados sensíveis mascarados
        if ($erro.OutcomeUncertain) {
            # A requisição pode ter sido processada: consulte a nota antes de emitir de novo.
        }
    }
}
```

O SDK não repete requisições automaticamente. Se uma emissão ou um cancelamento terminar com resultado desconhecido (`OutcomeUncertain` verdadeiro), consulte o documento antes de tentar novamente, para não emitir em duplicidade.

## Métodos disponíveis

**NF-e e NFC-e** — `New-WebmaniaCompanyClient`

- **Submit-WebmaniaNfeDocument**: Emissão de NF-e ou NFC-e junto ao SEFAZ.
- **Get-WebmaniaNfeDocument**: Consulta da nota fiscal pelo UUID, pela chave de acesso ou pelo ID do pedido.
- **Stop-WebmaniaNfeDocument**: Cancelamento de NF-e ou NFC-e.
- **New-WebmaniaNfeCorrection**: Carta de correção.
- **Clear-WebmaniaNfeNumbering**: Inutilização de sequência de numeração.
- **Submit-WebmaniaNfeReturn**: Emissão de NF-e de devolução.
- **Submit-WebmaniaNfeComplement**: Emissão de NF-e complementar.
- **Submit-WebmaniaNfeAdjustment**: Emissão de NF-e de ajuste.
- **New-WebmaniaNfeManifestation**: Manifestação do destinatário.
- **New-WebmaniaNfePaymentEvent** / **Stop-WebmaniaNfePaymentEvent**: Evento de conciliação financeira (ECONF) e o seu cancelamento.
- **New-WebmaniaNfeIbsCbsEvent** / **Stop-WebmaniaNfeIbsCbsEvent**: Eventos de IBS/CBS e o seu cancelamento.
- **Get-WebmaniaNfeTaxClasses** / **Set-WebmaniaNfeTaxClasses** / **Remove-WebmaniaNfeTaxClasses**: Classes de imposto.
- **Invoke-WebmaniaFiscalReport**: Relatórios fiscais.
- **Set-WebmaniaFiscalCompany**: Atualização dos dados da empresa emissora.
- **Get-WebmaniaNfeSefazStatus**: Verifica se o SEFAZ está online ou offline.
- **Get-WebmaniaNfeCertificateValidity**: Verifica quantos dias faltam para o certificado A1 expirar.

**NFS-e** — `New-WebmaniaIssuerClient`

- **Submit-WebmaniaEmitterNfse**: Emissão de NFS-e a partir de RPS.
- **Get-WebmaniaEmitterNfse**: Consulta da NFS-e.
- **Stop-WebmaniaEmitterNfse**: Cancelamento da NFS-e.
- **Set-WebmaniaEmitterNfseReplacement**: Substituição de NFS-e.
- **Submit-WebmaniaEmitterNfseManifestation**: Manifestação sobre NFS-e nacional.
- **Get-WebmaniaEmitterNfseProviderStatus**: Recursos do provedor de NFS-e do município da empresa.

**CT-e e CT-e OS** — `New-WebmaniaIssuerClient`

- **Submit-WebmaniaEmitterCte** / **Submit-WebmaniaEmitterSimplifiedCte**: Emissão de CT-e, CT-e OS e CT-e simplificado.
- **Get-WebmaniaEmitterCte**: Consulta do CT-e.
- **Stop-WebmaniaEmitterCte**: Cancelamento do CT-e.
- **Edit-WebmaniaEmitterCteCorrection**: Carta de correção do CT-e.
- **Approve-WebmaniaEmitterCteDelivery** / **Stop-WebmaniaEmitterCteDelivery**: Comprovante de entrega e o seu cancelamento.
- **Join-WebmaniaEmitterCtePayment** / **Stop-WebmaniaEmitterCtePaymentLink** / **Get-WebmaniaEmitterCtePaymentEvents**: Eventos de pagamento do CT-e.

**MDF-e** — `New-WebmaniaIssuerClient`

- **Submit-WebmaniaEmitterMdfe**: Emissão do MDF-e.
- **Get-WebmaniaEmitterMdfe**: Consulta do MDF-e pela chave de acesso.
- **Close-WebmaniaEmitterMdfe**: Encerramento do MDF-e.
- **Stop-WebmaniaEmitterMdfe**: Cancelamento do MDF-e.
- **Add-WebmaniaEmitterMdfeConductor**: Inclusão de condutor.

**NFCom e DC-e** — `New-WebmaniaIssuerClient`

- **Submit-WebmaniaEmitterNfcom** / **Get-WebmaniaEmitterNfcom** / **Stop-WebmaniaEmitterNfcom**: Emissão, consulta e cancelamento da NFCom.
- **Get-WebmaniaEmitterNfcomPaymentEvents**: Eventos de pagamento da NFCom.
- **Get-WebmaniaEmitterNfcomServiceStatus**: Disponibilidade do serviço da NFCom no SEFAZ.
- **Submit-WebmaniaEmitterDce** / **Get-WebmaniaEmitterDce** / **Stop-WebmaniaEmitterDce**: Emissão, consulta e cancelamento da DC-e.

**Arquivos (XML e PDF)** — `New-WebmaniaApi1FilesCompanyClient` (NF-e) e `New-WebmaniaApi2FilesCompanyBearerClient` (demais documentos)

- **Receive-WebmaniaNfeDanfe** / **Receive-WebmaniaNfeSimpleDanfe** / **Receive-WebmaniaNfeLabelDanfe**: DANFE completo, simplificado e etiqueta.
- **Receive-WebmaniaNfeXml** / **Receive-WebmaniaNfeCancellationXml**: XML da NF-e e do cancelamento.
- **Receive-WebmaniaNfeCorrectionPdf** / **Receive-WebmaniaNfeCorrectionXml**: PDF e XML da carta de correção.
- **Get-WebmaniaFileNfseXml** / **Get-WebmaniaFileNfsePdf** / **Get-WebmaniaFileNfseRpsPdf**: XML e PDF da NFS-e e PDF do RPS.
- **Get-WebmaniaFileCteXml** / **Get-WebmaniaFileCtePdf** / **Get-WebmaniaFileMdfeXml** / **Get-WebmaniaFileMdfePdf** / **Get-WebmaniaFileNfcomXml** / **Get-WebmaniaFileNfcomPdf** / **Get-WebmaniaFileDceXml** / **Get-WebmaniaFileDcePdf**: XML e PDF de CT-e, MDF-e, NFCom e DC-e.

**Monitor Fiscal** — `New-WebmaniaMonitorClient`

- **Search-WebmaniaMonitorDocuments** / **Get-WebmaniaMonitorDocument** / **Get-WebmaniaMonitorDocumentEvents**: Busca e consulta de documentos recebidos e do histórico de eventos.
- **Submit-WebmaniaMonitorDocumentManifestation**: Manifestação do destinatário.
- **Import-WebmaniaMonitorDocument** / **Get-WebmaniaMonitorImportStatus**: Importação por chave de acesso, XML ou ZIP.
- **Get-WebmaniaMonitorCompanies** / **New-WebmaniaMonitorCompany** / **Set-WebmaniaMonitorCompany**: Empresas monitoradas.

**Gerencial B2B** — `New-WebmaniaResellerClient`

- **New-WebmaniaB2bV1Companies** / **Get-WebmaniaB2bV1Companies** / **Get-WebmaniaB2bV1ProcessedRequests**: Cadastro de empresas, listagem e contagem de notas processadas por empresa.

A lista completa, com todos os comandos do Monitor Fiscal e dos arquivos, está em [docs/OPERATIONS.md](docs/OPERATIONS.md) e no próprio módulo (`Get-WebmaniaOperation`).

## Exemplo completo em homologação

A pasta [examples/homologacao](examples/homologacao) traz um programa que emite, consulta, baixa os arquivos e cancela uma NF-e e uma NFS-e em homologação, usando as credenciais das variáveis de ambiente. Por segurança, ele só envia requisições quando `WEBMANIA_LIVE=1` está definido e `WEBMANIA_LIVE_ALLOWED_HOSTS` lista os hosts da API. Para rodar só as consultas (status do SEFAZ, certificado e provedor de NFS-e):

```sh
WEBMANIA_LIVE=1 WEBMANIA_LIVE_SCOPE=readonly WEBMANIA_LIVE_ALLOWED_HOSTS=webmania.com.br,nfe.webmania.com.br,api.webmania.com.br pwsh -NoProfile -File examples/homologacao/run.ps1
```

As variáveis aceitas e o formato da saída estão em [examples/homologacao/README.md](examples/homologacao/README.md).

## Documentação

- Documentação da REST API: [NF-e / NFC-e](https://webmania.com.br/docs/rest-api-nfe/) · [NFS-e](https://webmania.com.br/docs/rest-api-nfse/) · [CT-e](https://webmania.com.br/docs/rest-api-cte/) · [MDF-e](https://webmania.com.br/docs/rest-api-mdfe/) · [NFCom](https://webmania.com.br/docs/rest-api-nfcom/) · [DC-e](https://webmania.com.br/docs/rest-api-dce/) · [Monitor Fiscal](https://webmania.com.br/docs/rest-api-monitor-fiscal/) · [Gerencial B2B](https://webmania.com.br/docs/rest-api-gerencial-b2b/)
- Contratos OpenAPI: [API 2.0](https://api.webmania.com.br/docs/openapi) e [NF-e](https://webmania.com.br/docs/rest-api-nfe/?format=openapi)
- Detalhes técnicos do SDK (URL base, arquivos, relatórios, limites): [docs/INTEGRATION.md](docs/INTEGRATION.md)
- Lista completa de comandos: [docs/OPERATIONS.md](docs/OPERATIONS.md)
- Clientes e credenciais de arquivos: [docs/CREDENTIALS.md](docs/CREDENTIALS.md)
- Desenvolvimento e testes do SDK: [docs/TESTING.md](docs/TESTING.md)
- Histórico de versões: [CHANGELOG.md](CHANGELOG.md)

## Suporte

Qualquer dúvida entre em contato na nossa [Central de Ajuda](https://ajuda.webmania.com.br) ou acesse o [Painel de Controle](https://webmania.com.br/painel/) para conversar em tempo real no Chat ou Abrir um chamado.

## Licença

Licença proprietária Webmania®: veja [LICENSE](LICENSE) e os [Termos de Uso](https://webmania.com.br/termos-de-uso/). As dependências de terceiros mantêm as suas próprias licenças.
