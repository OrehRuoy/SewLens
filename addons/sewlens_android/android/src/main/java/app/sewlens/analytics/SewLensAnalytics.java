package app.sewlens.analytics;

import android.os.Bundle;

import com.google.firebase.analytics.FirebaseAnalytics;
import com.google.firebase.crashlytics.FirebaseCrashlytics;

import org.godotengine.godot.Dictionary;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Map;

public class SewLensAnalytics extends GodotPlugin {
    private final Godot godot;

    public SewLensAnalytics(Godot godot) {
        super(godot);
        this.godot = godot;
    }

    @Override
    public String getPluginName() {
        return "SewLensAnalytics";
    }

    @UsedByGodot
    public void logEvent(String eventName, Dictionary params) {
        Bundle bundle = new Bundle();
        for (Map.Entry<String, Object> entry : params.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();
            if (value instanceof Number) {
                bundle.putDouble(key, ((Number) value).doubleValue());
            } else if (value != null) {
                bundle.putString(key, String.valueOf(value));
            }
        }
        Runnable log = () -> {
            var activity = godot.getActivity();
            if (activity == null) {
                return;
            }
            FirebaseAnalytics.getInstance(activity).logEvent(eventName, bundle);
        };
        var activity = godot.getActivity();
        if (activity != null) {
            activity.runOnUiThread(log);
        } else {
            log.run();
        }
    }

    @UsedByGodot
    public void setCustomKey(String key, String value) {
        FirebaseCrashlytics.getInstance().setCustomKey(key, value == null ? "" : value);
    }

    @UsedByGodot
    public void recordError(String message) {
        FirebaseCrashlytics.getInstance().recordException(new Exception(message == null ? "" : message));
    }

    @UsedByGodot
    public void testCrash() {
        throw new RuntimeException("SewLens test crash");
    }
}
