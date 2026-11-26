# INILOG Upload

Aplicativo portátil para Windows 10 e 11, com seleção de qualquer formato de arquivo, envio em blocos, progresso, cancelamento e link para compartilhar. Rodapé: Francisney Delmondes | INILOG; (61) 99363-0969; suporte@inilog.com; www.inilog.com.

## Uso

Abrir `upload.exe`, escolher um arquivo, clicar em **Carregar** e, ao concluir, clicar em **Copiar link**. O aplicativo continua sem senha. O arquivo permanece no servidor para o link continuar funcionando depois que o programa fechar.

O painel web em `/backup/` exige senha e oferece **Listar arquivos**, busca por nome, tamanho, data, download e cópia do link. A listagem reúne uploads concluídos e downloads existentes na raiz do próprio backup, excluindo os componentes e configurações do sistema. O diretório `/upload/` pertence a outro sistema e não foi alterado, copiado ou redirecionado.

O aplicativo não requer instalação, não pede administrador, não grava configurações, senha, histórico ou cópia temporária do arquivo no PC. O seletor usa a opção do Windows para não adicionar o arquivo à lista de documentos recentes. Isso não impede registros normais mantidos pelo próprio Windows, como os de execução do programa. O link copiado permanece na área de transferência por escolha do usuário.

## Compilação

A interface usa C# e Windows Forms do .NET Framework 4.x, disponível no Windows 10 e 11. A compilação usa o Roslyn das ferramentas de desenvolvimento do Visual Studio; não é necessário instalar essas ferramentas para utilizar o executável.

Executar `build/build.ps1` em um Windows com Visual Studio Build Tools e Python para compilar e executar as verificações. O executável resultante é AnyCPU, sem console, sem configuração externa e sem dependências de pacote. O tamanho da versão 1.0 é 30.720 bytes. O executável não possui assinatura comercial de código.

## Servidor

Publicar os arquivos de `server/` em `public_html/backup/`. Os dados são guardados fora de `public_html`, em `.inilog-upload`, com permissões privadas. A pasta pública `uploads/` roteia os links para o controlador de download; o conteúdo enviado é armazenado como dados e não é executado como PHP ou outro código no servidor.

A configuração privada contém `chunk_bytes`, `max_file_bytes`, `public_base` e `web_password_hash`. Gere o último campo com `password_hash` do PHP e guarde somente o hash, fora de `public_html`. A senha não está nos fontes nem no executável. Sem esse campo, o painel web permanece fechado; a API nativa mantém seu protocolo sem senha.

`server/panel.php` cuida do login, sessão, CSRF e listagem. O cookie usa HttpOnly, SameSite=Lax e Secure em HTTPS, restrito ao caminho do painel. A sessão expira após oito horas de inatividade e é renovada no login; alterar o hash invalida sessões anteriores. Solicitações da interface web usam a sessão e o cabeçalho `X-Inilog-Web-CSRF`. A API nativa permanece pública conforme a decisão do proprietário; a senha protege o painel web e não cria autenticação no protocolo do executável.

O padrão usa blocos de 4 MB, até 20 GB por arquivo, sujeito ao espaço disponível e aos limites da hospedagem. Os blocos têm verificação SHA-256; o aplicativo verifica também o arquivo completo. Arquivos de mesmo nome geram links diferentes e não são sobrescritos. Envios parciais abandonados são limpos após 24 horas na próxima inicialização de upload; arquivos concluídos não são apagados automaticamente.

Os links são públicos no formato `https://inilog.com/backup/uploads/<identificador>`. O nome e o formato originais são enviados no cabeçalho de download. Não é necessário banco de dados. O recebimento multipart no campo legado `file` continua disponível após login no painel, com o campo `csrf`, retornando o link gerado.

## Verificações

- 37 verificações do cliente no Windows: arquivo vazio, Unicode, múltiplos blocos, reenvio sem duplicação, cancelamento, integridade, layout e rodapé.
- 100 verificações do receptor PHP: formatos diversos, nomes especiais, download público, HEAD, download parcial, rejeição de conteúdo incompleto/corrompido, login, CSRF, sessão, listagem protegida, logout e multipart autenticado.
- `tests/LiveSmoke.cs` valida o cliente compilado contra o endereço real usando arquivos de demonstração, incluindo mais de um bloco e conteúdo PHP servido sem execução.

Fazer backup do código e do diretório privado antes de atualizar. Os testes e as ferramentas de compilação não devem ser publicados dentro do diretório web.
