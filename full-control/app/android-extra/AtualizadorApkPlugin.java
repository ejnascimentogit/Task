package br.com.taskfull.app;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/** Baixa o APK novo dentro do app e abre direto a tela de instalar/atualizar do Android. */
@CapacitorPlugin(name = "AtualizadorApk")
public class AtualizadorApkPlugin extends Plugin {
    private static final String PREFIXO = "https://github.com/ejnascimentogit/Task/releases/download/taskfull-android/";

    private boolean podeInstalar() {
        return Build.VERSION.SDK_INT < 26 || getContext().getPackageManager().canRequestPackageInstalls();
    }

    @PluginMethod
    public void podeInstalar(PluginCall call) {
        JSObject r = new JSObject();
        r.put("pode", podeInstalar());
        call.resolve(r);
    }

    /** Abre a tela do Android onde a pessoa libera "instalar apps desta fonte" para o Task Full (uma vez só). */
    @PluginMethod
    public void pedirPermissao(PluginCall call) {
        Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getContext().getPackageName()));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        getContext().startActivity(i);
        call.resolve();
    }

    @PluginMethod
    public void baixarEInstalar(final PluginCall call) {
        final String url = call.getString("url", PREFIXO + "taskfull.apk");
        if (url == null || !url.startsWith(PREFIXO)) { call.reject("Endereço não permitido."); return; }
        if (!podeInstalar()) { call.reject("sem_permissao"); return; }
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    File dir = new File(getContext().getCacheDir(), "apk");
                    if (!dir.exists()) dir.mkdirs();
                    File arq = new File(dir, "taskfull.apk");
                    if (arq.exists()) arq.delete();
                    HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
                    c.setConnectTimeout(20000);
                    c.setReadTimeout(30000);
                    c.setInstanceFollowRedirects(true);
                    if (c.getResponseCode() != 200) { call.reject("O servidor respondeu " + c.getResponseCode() + ". Se acabou de publicar, espere uns 5 minutos."); return; }
                    long total = c.getContentLengthLong();
                    InputStream in = c.getInputStream();
                    FileOutputStream out = new FileOutputStream(arq);
                    byte[] buf = new byte[65536];
                    long lido = 0; int ult = -1; int n;
                    while ((n = in.read(buf)) > 0) {
                        out.write(buf, 0, n);
                        lido += n;
                        if (total > 0) {
                            int pct = (int) (lido * 100 / total);
                            if (pct != ult) { ult = pct; JSObject p = new JSObject(); p.put("pct", pct); notifyListeners("progresso", p); }
                        }
                    }
                    out.close(); in.close(); c.disconnect();
                    Uri uri = FileProvider.getUriForFile(getContext(), getContext().getPackageName() + ".fileprovider", arq);
                    Intent i = new Intent(Intent.ACTION_VIEW);
                    i.setDataAndType(uri, "application/vnd.android.package-archive");
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                    getContext().startActivity(i);
                    call.resolve();
                } catch (Exception e) {
                    call.reject("Falha ao baixar: " + e.getMessage());
                }
            }
        }).start();
    }
}
