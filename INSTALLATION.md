# Hitman GO — instalação (BYO-data) / installation (BYO-data)

Este pacote contém **apenas o port**. O jogo é seu e não é distribuído aqui.
*This package contains the port only. The game is yours and is not distributed here.*

## 1. Copie o pacote / Copy the package

Descompacte o ZIP na pasta de ports do seu aparelho:

- ArkOS / muOS / Batocera e afins: `/roms/ports/`
- NextOS Elite: `.sh` em `/storage/roms/ports_scripts/`, pasta `hitmango` em `/storage/roms/ports/`

## 2. Coloque seu APK / Drop your APK

Copie o APK/APKM/XAPK da sua cópia legal do jogo
(`com.squareenixmontreal.hitmango`, versão **1.18.1**, arm64-v8a) para:

```text
ports/hitmango/gamedata/
```

O nome do arquivo não importa: o NXExtract identifica a versão pelo conteúdo.
*The filename does not matter: NXExtract identifies the build by content.*

## 3. Rode pelo menu / Launch from the menu

Na primeira execução o extrator valida ABI, tamanhos e assinaturas, instala os
dados de forma transacional (com barra de progresso) e abre o jogo. O seu
arquivo original **nunca é apagado**. Se o APK for de outra build, o erro diz
exatamente isso — "build diferente" — em vez de fingir que falta arquivo.

Nas aberturas seguintes um marker valida os dados em milissegundos, sem
reescanear o cartão.

**SELECT + START** salva e volta ao frontend. / *SELECT + START saves and
returns to the frontend.*

## Saves

Ficam na pasta `home` dentro de `ports/hitmango` e sobrevivem a atualizações
do port. *Saves live in the `home` folder inside `ports/hitmango` and survive
port updates.*

## Controles / Controls

- **D-pad / analógico esquerdo** — move o Agente 47 no tabuleiro
- **A** — confirmar / clique do cursor
- **B** — voltar
- **Analógico direito** — cursor de fallback para telas de toque
- **START** — painel de objetivos
- **SELECT + START** — salvar e sair

## Aparelhos / Devices

Validado fisicamente no **R36T clone/ArkOS** (Mali-G31, 640×480, 640 MB) e no
**NextOS Elite** (Mali-450, 1280×720). Nos demais CFWs AArch64 o launcher
detecta vídeo, áudio, resolução e controle em runtime; deve funcionar, mas só
declaramos validado o que foi rodado de verdade.
