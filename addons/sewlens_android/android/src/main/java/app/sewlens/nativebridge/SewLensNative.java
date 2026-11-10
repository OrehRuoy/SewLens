package app.sewlens.nativebridge;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.util.Log;

import androidx.core.content.FileProvider;

import com.google.android.play.core.review.ReviewManagerFactory;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashSet;
import java.util.Set;

/**
 * Share sheet, camera and photo picker for scripts/autoload/native_bridge.gd.
 *
 * The camera goes through ACTION_IMAGE_CAPTURE, so the app needs no CAMERA
 * permission (declaring it would make that intent require a runtime grant).
 * The library uses the system photo picker, which needs no storage permission.
 * Files go through Godot's own FileProvider, whose files-path "/" covers user://.
 */
public class SewLensNative extends GodotPlugin {
    private static final String TAG = "SewLensNative";
    private static final int REQUEST_CAMERA = 0x5E01;
    private static final int REQUEST_LIBRARY = 0x5E02;
    private static final int MAX_SIDE = 1600;

    private String pendingOutput = "";
    private File cameraFile;

    public SewLensNative(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "SewLensNative";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("photo_finished", String.class, String.class));
        signals.add(new SignalInfo("share_finished", String.class));
        signals.add(new SignalInfo("billing_finished", String.class));
        return signals;
    }

    private SewLensBilling billing;

    private SewLensBilling billing() {
        if (billing == null) {
            billing = new SewLensBilling(json -> runOnRenderThread(() -> emitSignal("billing_finished", json)));
        }
        return billing;
    }

    @UsedByGodot
    public void queryProducts() {
        billing().queryProducts(getActivity());
    }

    @UsedByGodot
    public void purchase(String productId) {
        billing().purchase(getActivity(), productId);
    }

    @UsedByGodot
    public void restorePurchases() {
        billing().restore(getActivity());
    }

    @UsedByGodot
    public void finishPurchase(String transactionId) {
        billing().finish(getActivity(), transactionId);
    }

    @UsedByGodot
    public void requestReview() {
        Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        var manager = ReviewManagerFactory.create(activity);
        manager.requestReviewFlow().addOnCompleteListener(task -> {
            if (task.isSuccessful()) {
                manager.launchReviewFlow(activity, task.getResult());
            }
        });
    }

    private String authority(Activity activity) {
        return activity.getPackageName() + ".fileprovider";
    }

    @UsedByGodot
    public void pickPhoto(String source, String outputPath) {
        Activity activity = getActivity();
        if (activity == null) {
            emitPhoto("error", "");
            return;
        }
        pendingOutput = outputPath;
        activity.runOnUiThread(() -> {
            try {
                if ("camera".equals(source)) {
                    startCamera(activity);
                } else {
                    startLibrary(activity);
                }
            } catch (ActivityNotFoundException e) {
                Log.w(TAG, "No activity for " + source + ": " + e.getMessage());
                emitPhoto("unavailable", "");
            } catch (Exception e) {
                Log.w(TAG, "Photo request failed: " + e.getMessage());
                emitPhoto("error", "");
            }
        });
    }

    private void startCamera(Activity activity) throws Exception {
        File dir = new File(activity.getFilesDir(), "camera");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("camera folder");
        }
        cameraFile = new File(dir, "capture.jpg");
        if (cameraFile.exists() && !cameraFile.delete()) {
            Log.w(TAG, "Old capture was not deleted");
        }
        Uri uri = FileProvider.getUriForFile(activity, authority(activity), cameraFile);
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        intent.putExtra(MediaStore.EXTRA_OUTPUT, uri);
        intent.setClipData(ClipData.newRawUri("output", uri));
        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
        activity.startActivityForResult(intent, REQUEST_CAMERA);
    }

    private void startLibrary(Activity activity) {
        Intent intent;
        if (Build.VERSION.SDK_INT >= 33) {
            intent = new Intent(MediaStore.ACTION_PICK_IMAGES);
        } else {
            intent = new Intent(Intent.ACTION_GET_CONTENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
        }
        intent.setType("image/*");
        activity.startActivityForResult(intent, REQUEST_LIBRARY);
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_CAMERA && requestCode != REQUEST_LIBRARY) {
            return;
        }
        if (resultCode != Activity.RESULT_OK) {
            emitPhoto("cancelled", "");
            return;
        }
        Activity activity = getActivity();
        Uri source = null;
        if (requestCode == REQUEST_CAMERA && cameraFile != null && cameraFile.length() > 0) {
            source = Uri.fromFile(cameraFile);
        } else if (requestCode == REQUEST_LIBRARY && data != null) {
            source = data.getData();
        }
        if (activity == null || source == null) {
            emitPhoto("error", "");
            return;
        }
        final Uri input = source;
        final String output = pendingOutput;
        new Thread(() -> {
            boolean ok = writeScaledJpeg(activity, input, output);
            emitPhoto(ok ? "ok" : "error", ok ? output : "");
        }, "SewLensPhoto").start();
    }

    private InputStream open(Activity activity, Uri uri) throws Exception {
        if ("file".equals(uri.getScheme())) {
            return new java.io.FileInputStream(new File(uri.getPath()));
        }
        return activity.getContentResolver().openInputStream(uri);
    }

    private boolean writeScaledJpeg(Activity activity, Uri uri, String outputPath) {
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            try (InputStream in = open(activity, uri)) {
                BitmapFactory.decodeStream(in, null, bounds);
            }
            int longest = Math.max(bounds.outWidth, bounds.outHeight);
            if (longest <= 0) {
                return false;
            }
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inSampleSize = 1;
            while (longest / (options.inSampleSize * 2) >= MAX_SIDE) {
                options.inSampleSize *= 2;
            }
            Bitmap bitmap;
            try (InputStream in = open(activity, uri)) {
                bitmap = BitmapFactory.decodeStream(in, null, options);
            }
            if (bitmap == null) {
                return false;
            }
            int rotation = 0;
            try (InputStream in = open(activity, uri)) {
                int orientation = new ExifInterface(in).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
                if (orientation == ExifInterface.ORIENTATION_ROTATE_90) rotation = 90;
                if (orientation == ExifInterface.ORIENTATION_ROTATE_180) rotation = 180;
                if (orientation == ExifInterface.ORIENTATION_ROTATE_270) rotation = 270;
            } catch (Exception e) {
                Log.i(TAG, "No EXIF orientation: " + e.getMessage());
            }
            float scale = Math.min(1f, (float) MAX_SIDE / Math.max(bitmap.getWidth(), bitmap.getHeight()));
            Matrix matrix = new Matrix();
            matrix.postScale(scale, scale);
            matrix.postRotate(rotation);
            Bitmap upright = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
            File target = new File(outputPath);
            File parent = target.getParentFile();
            if (parent != null && !parent.exists() && !parent.mkdirs()) {
                return false;
            }
            try (FileOutputStream out = new FileOutputStream(target)) {
                upright.compress(Bitmap.CompressFormat.JPEG, 85, out);
            }
            return target.length() > 0;
        } catch (Exception e) {
            Log.w(TAG, "Photo could not be saved: " + e.getMessage());
            return false;
        }
    }

    @UsedByGodot
    public void shareFile(String path, String mime, String title) {
        Activity activity = getActivity();
        File file = new File(path);
        if (activity == null || !file.isFile()) {
            emitShare("error");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                Uri uri = FileProvider.getUriForFile(activity, authority(activity), file);
                Intent send = new Intent(Intent.ACTION_SEND);
                send.setType(mime);
                send.putExtra(Intent.EXTRA_STREAM, uri);
                send.putExtra(Intent.EXTRA_SUBJECT, title);
                send.setClipData(ClipData.newRawUri(title, uri));
                send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                Intent chooser = Intent.createChooser(send, title);
                chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                activity.startActivity(chooser);
                emitShare("ok");
            } catch (Exception e) {
                Log.w(TAG, "Share failed: " + e.getMessage());
                emitShare("error");
            }
        });
    }

    private void emitPhoto(String status, String path) {
        Log.i(TAG, "photo_finished " + status);
        runOnRenderThread(() -> emitSignal("photo_finished", status, path));
    }

    private void emitShare(String status) {
        Log.i(TAG, "share_finished " + status);
        runOnRenderThread(() -> emitSignal("share_finished", status));
    }
}
