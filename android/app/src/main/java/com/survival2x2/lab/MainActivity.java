package com.survival2x2.lab;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;
import android.view.Display;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.ConsoleMessage;
import android.webkit.MimeTypeMap;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.util.Log;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

/**
 * Casca nativa do jogo: um WebView em tela cheia que serve o jogo web (WebGL2) direto dos assets do APK
 * através de https://appassets.local/ (origem segura -> módulos ES, fetch, WebAudio e Gamepad funcionam).
 * Compatível com Android 7.0 (API 24) até Android 16 (API 36).
 */
public class MainActivity extends Activity {
    private static final String TAG = "Sobrevivencia2x2";
    private static final String HOST = "appassets.local";
    private WebView web;

    @SuppressLint({"SetJavaScriptEnabled", "ClickableViewAccessibility"})
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Window w = getWindow();
        w.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON | WindowManager.LayoutParams.FLAG_FULLSCREEN);
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams lp = w.getAttributes();
            lp.layoutInDisplayCutoutMode = Build.VERSION.SDK_INT >= 30
                    ? WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                    : WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            w.setAttributes(lp);
        }
        requestHighRefreshRate();
        if (Build.VERSION.SDK_INT >= 24) {
            try { w.setSustainedPerformanceMode(true); } catch (Throwable ignored) { }
        }

        boolean debuggable = (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        if (debuggable) WebView.setWebContentsDebuggingEnabled(true);

        web = new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setScrollBarStyle(View.SCROLLBARS_INSIDE_OVERLAY);
        web.setLongClickable(false);
        web.setHapticFeedbackEnabled(false);
        web.setOnLongClickListener(v -> true);
        web.setLayerType(View.LAYER_TYPE_NONE, null);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setTextZoom(100);

        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onConsoleMessage(ConsoleMessage m) {
                Log.d(TAG, m.message() + " (" + m.sourceId() + ":" + m.lineNumber() + ")");
                return true;
            }
        });
        web.setWebViewClient(new WebViewClient() {
            @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return serve(request.getUrl().getHost(), request.getUrl().getPath());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !HOST.equals(request.getUrl().getHost()); // bloqueia navegação externa
            }
        });
        setContentView(web);
        hideSystemUi();
        web.loadUrl("https://" + HOST + "/index.html");
    }

    // ---- serve os arquivos de assets/ (o diretório www/ do projeto) como se fosse um servidor https
    private WebResourceResponse serve(String host, String path) {
        if (!HOST.equals(host)) return null;
        if (path == null || path.equals("/") || path.isEmpty()) path = "/index.html";
        String p = path.startsWith("/") ? path.substring(1) : path;
        try {
            InputStream in = getAssets().open(p);
            String mime = mimeOf(p);
            WebResourceResponse r = new WebResourceResponse(mime, mime.startsWith("text/") || mime.contains("javascript") || mime.contains("json") ? "UTF-8" : null, in);
            Map<String, String> h = new HashMap<>();
            h.put("Access-Control-Allow-Origin", "*");
            h.put("Cache-Control", "max-age=3600");
            r.setResponseHeaders(h);
            return r;
        } catch (IOException e) {
            WebResourceResponse r = new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", new HashMap<>(), new java.io.ByteArrayInputStream(new byte[0]));
            return r;
        }
    }

    private static String mimeOf(String p) {
        String l = p.toLowerCase();
        if (l.endsWith(".js") || l.endsWith(".mjs")) return "text/javascript";
        if (l.endsWith(".html")) return "text/html";
        if (l.endsWith(".css")) return "text/css";
        if (l.endsWith(".json")) return "application/json";
        if (l.endsWith(".glb")) return "model/gltf-binary";
        if (l.endsWith(".webp")) return "image/webp";
        if (l.endsWith(".jpg") || l.endsWith(".jpeg")) return "image/jpeg";
        if (l.endsWith(".png")) return "image/png";
        if (l.endsWith(".svg")) return "image/svg+xml";
        if (l.endsWith(".wasm")) return "application/wasm";
        String ext = MimeTypeMap.getFileExtensionFromUrl(p);
        String m = ext == null ? null : MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return m != null ? m : "application/octet-stream";
    }

    // ---- 90/120 Hz (POCO X7 Pro: tela 120 Hz)
    private void requestHighRefreshRate() {
        try {
            Display d = Build.VERSION.SDK_INT >= 30 ? getDisplay() : getWindowManager().getDefaultDisplay();
            if (d == null) return;
            WindowManager.LayoutParams lp = getWindow().getAttributes();
            if (Build.VERSION.SDK_INT >= 23) {
                Display.Mode cur = d.getMode();
                Display.Mode best = cur;
                for (Display.Mode m : d.getSupportedModes()) {
                    if (m.getPhysicalWidth() == cur.getPhysicalWidth() && m.getPhysicalHeight() == cur.getPhysicalHeight()
                            && m.getRefreshRate() > best.getRefreshRate() && m.getRefreshRate() <= 121f) best = m;
                }
                lp.preferredDisplayModeId = best.getModeId();
            }
            lp.preferredRefreshRate = 120f;
            getWindow().setAttributes(lp);
        } catch (Throwable t) { Log.w(TAG, "refresh rate: " + t); }
    }

    private void hideSystemUi() {
        Window w = getWindow();
        if (Build.VERSION.SDK_INT >= 30) {
            w.setDecorFitsSystemWindows(false);
            WindowInsetsController c = w.getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            w.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
    }

    @Override public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemUi();
    }
    @Override protected void onPause() { super.onPause(); if (web != null) { web.onPause(); web.pauseTimers(); } }
    @Override protected void onResume() { super.onResume(); if (web != null) { web.resumeTimers(); web.onResume(); } hideSystemUi(); }
    @Override protected void onDestroy() { if (web != null) { web.destroy(); web = null; } super.onDestroy(); }

    @Override public void onBackPressed() {
        // botão voltar abre/fecha o menu do jogo em vez de sair
        if (web != null) web.evaluateJavascript("(function(){var g=window.game;if(g&&g.ui){if(g.ui.invOpen)g.ui.closeInv();else g.ui.toggleMenu();return 1}return 0})()", null);
        else super.onBackPressed();
    }
}
