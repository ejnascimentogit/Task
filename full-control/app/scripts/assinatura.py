# Fixa a chave de assinatura do APK e numera a versão (rodado pelo workflow depois de "cap add android").
# Sem isto, cada compilação no GitHub gera uma chave nova e o Android recusa atualizar o app por cima.
import os, re, sys
p = sys.argv[1]
s = open(p).read()
assert 'signingConfigs' not in s, 'build.gradle já tem signingConfigs'
bloco = """android {
    signingConfigs {
        debug {
            storeFile rootProject.file('../signing/debug.keystore')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
    }
"""
assert s.count('android {\n') == 1
s = s.replace('android {\n', bloco, 1)
n = os.environ.get('GITHUB_RUN_NUMBER', '1')
assert s.count('versionCode 1\n') == 1
s = s.replace('versionCode 1\n', 'versionCode %s\n' % n, 1)
s = s.replace('versionName "1.0"', 'versionName "1.0.%s"' % n, 1)
open(p, 'w').write(s)
import json
open('www/nodejs/versao.json', 'w').write(json.dumps({'versao': '1.0.%s' % n}))
print('assinatura fixa e versionCode', n)
