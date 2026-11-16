package app.sewlens.nativebridge;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.media.ExifInterface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.util.Log;

import androidx.core.content.FileProvider;

import com.google.android.play.core.review.ReviewManagerFactory;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
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
    private static final int REQUEST_SAVE = 0x5E03;
    private static final int MAX_SIDE = 1600;

    private String pendingOutput = "";
    private String pendingSavePath = "";
    private File cameraFile;

    public SewLensNative(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "SewLensNative";
    }

    /**
     * Godot registers these names even when the @UsedByGodot annotation is not
     * visible to reflection. The default implementation returns an empty list.
     */
    @Override
    public List<String> getPluginMethods() {
        return Arrays.asList(
                "billingPluginInfo",
                "queryProducts",
                "purchase",
                "restorePurchases",
                "finishPurchase",
                "requestReview",
                "pickPhoto",
                "shareFile",
                "printPdf",
                "savePdf",
                "openPdf");
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("photo_finished", String.class, String.class));
        signals.add(new SignalInfo("share_finished", String.class));
        signals.add(new SignalInfo("print_finished", String.class));
        signals.add(new SignalInfo("save_finished", String.class));
        signals.add(new SignalInfo("open_finished", String.class));
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
    public String billingPluginInfo() {
        Activity activity = getActivity();
        String pkg = activity == null ? "" : activity.getPackageName();
        return "SewLensNative package=" + pkg;
    }

    @UsedByGodot
    public void queryProducts() {
        runBilling(activity -> billing().queryProducts(activity));
    }

    @UsedByGodot
    public void purchase(String productId) {
        runBilling(activity -> billing().purchase(activity, productId));
    }

    @UsedByGodot
    public void restorePurchases() {
        runBilling(activity -> billing().restore(activity));
    }

    @UsedByGodot
    public void finishPurchase(String transactionId) {
        runBilling(activity -> billing().finish(activity, transactionId));
    }

    /**
     * Play Billing binds its service from the Android main thread. Godot calls
     * @UsedByGodot methods on the render thread, and that bind then never calls back.
     */
    private void runBilling(java.util.function.Consumer<Activity> work) {
        Activity activity = getActivity();
        if (activity == null) {
            billing().fail("connecting", -1, "no activity");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                work.accept(activity);
            } catch (RuntimeException e) {
                Log.e(TAG, "Billing call failed", e);
                billing().fail("connecting", -1, e.toString());
            }
        });
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
        if (requestCode == REQUEST_SAVE) {
            handleSaveResult(resultCode, data);
            return;
        }
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
                emitShare("opened");
            } catch (Exception e) {
                Log.w(TAG, "Share failed: " + e.getMessage());
                emitShare("error");
            }
        });
    }

    @UsedByGodot
    public void printPdf(String path, String jobName) {
        Activity activity = getActivity();
        File file = new File(path);
        if (activity == null || !file.isFile()) {
            emitPrint("error");
            return;
        }
        String name = jobName == null || jobName.isEmpty() ? file.getName() : jobName;
        activity.runOnUiThread(() -> {
            try {
                PrintManager manager = (PrintManager) activity.getSystemService(Context.PRINT_SERVICE);
                if (manager == null) {
                    emitPrint("error");
                    return;
                }
                manager.print(name, new PdfPassThrough(file, name), new PrintAttributes.Builder().build());
                emitPrint("started");
            } catch (Exception e) {
                Log.w(TAG, "Print failed: " + e.getMessage());
                emitPrint("error");
            }
        });
    }

    @UsedByGodot
    public void savePdf(String path, String suggestedName) {
        Activity activity = getActivity();
        File file = new File(path);
        if (activity == null || !file.isFile()) {
            emitSave("error");
            return;
        }
        pendingSavePath = path;
        String title = suggestedName == null || suggestedName.isEmpty() ? file.getName() : suggestedName;
        activity.runOnUiThread(() -> {
            try {
                Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                intent.setType("application/pdf");
                intent.putExtra(Intent.EXTRA_TITLE, title);
                activity.startActivityForResult(intent, REQUEST_SAVE);
            } catch (Exception e) {
                Log.w(TAG, "Save failed: " + e.getMessage());
                emitSave("error");
            }
        });
    }

    @UsedByGodot
    public void openPdf(String path) {
        Activity activity = getActivity();
        File file = new File(path);
        if (activity == null || !file.isFile()) {
            emitOpen("error");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                Uri uri = FileProvider.getUriForFile(activity, authority(activity), file);
                Intent view = new Intent(Intent.ACTION_VIEW);
                view.setDataAndType(uri, "application/pdf");
                view.setClipData(ClipData.newRawUri(file.getName(), uri));
                view.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                activity.startActivity(view);
                emitOpen("ok");
            } catch (ActivityNotFoundException e) {
                emitOpen("error");
            } catch (Exception e) {
                Log.w(TAG, "Open failed: " + e.getMessage());
                emitOpen("error");
            }
        });
    }

    private void handleSaveResult(int resultCode, Intent data) {
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            emitSave("cancelled");
            return;
        }
        Activity activity = getActivity();
        Uri destination = data.getData();
        String source = pendingSavePath;
        if (activity == null || source == null || source.isEmpty()) {
            emitSave("error");
            return;
        }
        new Thread(() -> emitSave(copyToUri(activity, destination, source) ? "ok" : "error"), "SewLensSave").start();
    }

    private boolean copyToUri(Activity activity, Uri uri, String path) {
        try (InputStream in = new FileInputStream(path); OutputStream out = activity.getContentResolver().openOutputStream(uri)) {
            if (out == null) {
                return false;
            }
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) >= 0) {
                out.write(buffer, 0, read);
            }
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Save copy failed: " + e.getMessage());
            return false;
        }
    }

    /** Copies the PDF bytes unchanged so the printer keeps the page size. */
    private static final class PdfPassThrough extends PrintDocumentAdapter {
        private final File file;
        private final String name;

        PdfPassThrough(File file, String name) {
            this.file = file;
            this.name = name;
        }

        @Override
        public void onLayout(PrintAttributes oldAttributes, PrintAttributes newAttributes, CancellationSignal cancellationSignal, LayoutResultCallback callback, Bundle extras) {
            if (cancellationSignal.isCanceled()) {
                callback.onLayoutCancelled();
                return;
            }
            PrintDocumentInfo info = new PrintDocumentInfo.Builder(name)
                    .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                    .setPageCount(PrintDocumentInfo.PAGE_COUNT_UNKNOWN)
                    .build();
            callback.onLayoutFinished(info, true);
        }

        @Override
        public void onWrite(PageRange[] pages, ParcelFileDescriptor destination, CancellationSignal cancellationSignal, WriteResultCallback callback) {
            try (InputStream in = new FileInputStream(file); OutputStream out = new FileOutputStream(destination.getFileDescriptor())) {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = in.read(buffer)) >= 0) {
                    if (cancellationSignal.isCanceled()) {
                        callback.onWriteCancelled();
                        return;
                    }
                    out.write(buffer, 0, read);
                }
                callback.onWriteFinished(new PageRange[]{PageRange.ALL_PAGES});
            } catch (Exception e) {
                callback.onWriteFailed(e.getMessage());
            }
        }
    }

    private void emitPhoto(String status, String path) {
        Log.i(TAG, "photo_finished " + status);
        runOnRenderThread(() -> emitSignal("photo_finished", status, path));
    }

    private void emitShare(String status) {
        Log.i(TAG, "share_finished " + status);
        runOnRenderThread(() -> emitSignal("share_finished", status));
    }

    private void emitPrint(String status) {
        Log.i(TAG, "print_finished " + status);
        runOnRenderThread(() -> emitSignal("print_finished", status));
    }

    private void emitSave(String status) {
        Log.i(TAG, "save_finished " + status);
        runOnRenderThread(() -> emitSignal("save_finished", status));
    }

    private void emitOpen(String status) {
        Log.i(TAG, "open_finished " + status);
        runOnRenderThread(() -> emitSignal("open_finished", status));
    }
}
