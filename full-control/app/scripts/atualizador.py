# Põe o plugin nativo "AtualizadorApk" no projeto Android gerado (rodado pelo workflow depois de "cap add android").
import glob, os, sys, shutil
raiz = 'android/app/src/main'
manifest = raiz + '/AndroidManifest.xml'
m = open(manifest).read()
if 'REQUEST_INSTALL_PACKAGES' not in m:
    a = '<uses-permission android:name="android.permission.INTERNET" />'
    assert m.count(a) == 1
    m = m.replace(a, a + '\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />')
    open(manifest, 'w').write(m)
acts = glob.glob(raiz + '/java/**/MainActivity.java', recursive=True)
assert len(acts) == 1, acts
pasta = os.path.dirname(acts[0])
shutil.copy('android-extra/AtualizadorApkPlugin.java', pasta + '/AtualizadorApkPlugin.java')
open(acts[0], 'w').write("""package br.com.taskfull.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(AtualizadorApkPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
""")
print('plugin AtualizadorApk instalado em', pasta)
