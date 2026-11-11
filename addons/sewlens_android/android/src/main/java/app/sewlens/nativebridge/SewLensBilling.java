package app.sewlens.nativebridge;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.android.billingclient.api.AcknowledgePurchaseParams;
import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.ConsumeParams;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.PurchasesUpdatedListener;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryProductDetailsResult;
import com.android.billingclient.api.QueryPurchasesParams;
import com.android.billingclient.api.UnfetchedProduct;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Google Play Billing for the consumable credit and the non-consumable unlock.
 * Localized prices come from ProductDetails. The purchase token goes to
 * verifyPurchase; this class does not grant an entitlement by itself.
 */
final class SewLensBilling implements PurchasesUpdatedListener {
    static final String CREDIT = "orehruoy.sewlens.credit";
    static final String UNLIMITED = "orehruoy.sewlens.unlimited";

    interface Listener {
        void onBilling(String json);
    }

    private static final String TAG = "SEWLENS_BILLING";
    private static final String BILLING_ACTION = "com.android.vending.billing.InAppBillingService.BIND";
    private static final long SETUP_TIMEOUT_MS = 15_000L;
    private final Listener listener;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final AtomicInteger setupToken = new AtomicInteger();
    private Runnable setupTimeout;
    private BillingClient client;
    private String bundleId = "";
    private int lastProductCount = 0;
    private int visibleBillingServices = -1;
    private final Map<String, ProductDetails> products = new HashMap<>();
    private final List<String> lastUnfetched = new ArrayList<>();
    private String pendingFinish = "";

    SewLensBilling(Listener listener) {
        this.listener = listener;
    }

    void queryProducts(Activity activity) {
        ready(activity, () -> queryDetails());
    }

    void fail(String stage, int code, String message) {
        emit(report(stage, code, message, requestedIds(), new ArrayList<>(), 0));
    }

    void purchase(Activity activity, String productId) {
        ready(activity, () -> {
            ProductDetails details = products.get(productId);
            if (details == null) {
                queryDetailsThen(() -> launch(activity, productId));
                return;
            }
            launch(activity, productId);
        });
    }

    void restore(Activity activity) {
        ready(activity, () -> client.queryPurchasesAsync(
                QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),
                (result, purchases) -> {
                    if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
                        emit(report("connected", result.getResponseCode(), debugOf(result), requestedIds(), validIds(), 0));
                        return;
                    }
                    JSONArray rows = new JSONArray();
                    for (Purchase purchase : purchases) {
                        rows.put(purchaseJson(purchase));
                    }
                    try {
                        JSONObject payload = new JSONObject();
                        payload.put("status", "ok");
                        payload.put("receipts", rows);
                        emit(payload.toString());
                    } catch (Exception e) {
                        emit(status("error"));
                    }
                }));
    }

    void finish(Activity activity, String transactionId) {
        pendingFinish = transactionId == null ? "" : transactionId;
        ready(activity, () -> client.queryPurchasesAsync(
                QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),
                (result, purchases) -> {
                    for (Purchase purchase : purchases) {
                        if (pendingFinish.equals(purchase.getOrderId()) || pendingFinish.equals(purchase.getPurchaseToken())) {
                            settle(purchase);
                            return;
                        }
                    }
                    emit(status("ok"));
                }));
    }

    private void ready(Activity activity, Runnable next) {
        if (activity == null) {
            fail("connecting", -1, "no activity");
            return;
        }
        if (Looper.myLooper() != Looper.getMainLooper()) {
            activity.runOnUiThread(() -> ready(activity, next));
            return;
        }
        bundleId = activity.getPackageName();
        if (client != null && client.isReady()) {
            emitProgress("connected", "Play Billing already connected");
            next.run();
            return;
        }
        if (client != null) {
            try {
                client.endConnection();
            } catch (RuntimeException e) {
                Log.w(TAG, "endConnection " + e.getMessage());
            }
            client = null;
        }
        client = BillingClient.newBuilder(activity)
                .setListener(this)
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                .build();
        final int token = setupToken.incrementAndGet();
        if (setupTimeout != null) {
            mainHandler.removeCallbacks(setupTimeout);
        }
        Runnable timeout = () -> {
            if (!setupToken.compareAndSet(token, token + 1)) {
                return;
            }
            Log.w(TAG, "startConnection timed out before onBillingSetupFinished services=" + visibleBillingServices);
            emit(report("connecting", -1, "setup timeout, onBillingSetupFinished never called (Play billing services visible: " + visibleBillingServices + ", startConnection returned)", requestedIds(), new ArrayList<>(), 0));
        };
        setupTimeout = timeout;
        mainHandler.postDelayed(timeout, SETUP_TIMEOUT_MS);
        int services = visibleBillingServices(activity);
        visibleBillingServices = services;
        Log.i(TAG, "queryIntentServices action=" + BILLING_ACTION + " package=com.android.vending count=" + services + " thread=" + Thread.currentThread().getName());
        if (services == 0) {
            if (setupToken.compareAndSet(token, token + 1)) {
                mainHandler.removeCallbacks(timeout);
                emit(report("connecting", BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, "Play Billing service is not visible. The manifest needs queries for com.android.vending.", requestedIds(), new ArrayList<>(), 0));
            }
            return;
        }
        emitProgress("connecting", "startConnection");
        try {
            Log.i(TAG, "startConnection calling thread=" + Thread.currentThread().getName() + " services=" + services);
            client.startConnection(new BillingClientStateListener() {
                @Override
                public void onBillingSetupFinished(BillingResult result) {
                    if (!setupToken.compareAndSet(token, token + 1)) {
                        return;
                    }
                    mainHandler.removeCallbacks(timeout);
                    logResult("onBillingSetupFinished", result);
                    if (result.getResponseCode() == BillingClient.BillingResponseCode.OK && client != null && client.isReady()) {
                        Log.i(TAG, "Play Billing connected");
                        emitProgress("connected", "Play Billing connected");
                        activity.runOnUiThread(next);
                    } else {
                        String message = debugOf(result);
                        if (client == null || !client.isReady()) {
                            message = message.isEmpty() ? "BillingClient is not connected" : message;
                        }
                        emit(report("connecting", result.getResponseCode(), message, requestedIds(), new ArrayList<>(), 0));
                    }
                }

                @Override
                public void onBillingServiceDisconnected() {
                    Log.w(TAG, "onBillingServiceDisconnected thread=" + Thread.currentThread().getName());
                    if (!setupToken.compareAndSet(token, token + 1)) {
                        Log.w(TAG, "onBillingServiceDisconnected ignored because setup already finished");
                        return;
                    }
                    mainHandler.removeCallbacks(timeout);
                    emit(report("connecting", BillingClient.BillingResponseCode.SERVICE_DISCONNECTED, "onBillingServiceDisconnected", requestedIds(), new ArrayList<>(), 0));
                }
            });
            Log.i(TAG, "startConnection returned thread=" + Thread.currentThread().getName() + " services=" + services);
        } catch (RuntimeException e) {
            if (setupToken.compareAndSet(token, token + 1)) {
                mainHandler.removeCallbacks(timeout);
                Log.e(TAG, "startConnection threw", e);
                emit(report("connecting", -1, e.toString(), requestedIds(), new ArrayList<>(), 0));
            }
        }
    }

    private void queryDetails() {
        queryDetailsThen(() -> {
            try {
                JSONObject prices = new JSONObject();
                for (Map.Entry<String, ProductDetails> entry : products.entrySet()) {
                    String price = priceOf(entry.getValue());
                    if (!price.isEmpty()) {
                        prices.put(entry.getKey(), price);
                    }
                }
                if (prices.length() == 0) {
                    List<String> invalid = lastUnfetched.isEmpty() ? requestedIds() : lastUnfetched;
                    String message = lastProductCount == 0
                            ? "query returned 0 products with OK"
                            : "query returned " + lastProductCount + " products but none had a price";
                    emit(report("query_done", BillingClient.BillingResponseCode.OK, message, invalid, validIds(), lastProductCount));
                    return;
                }
                JSONObject payload = new JSONObject();
                payload.put("status", "ok");
                payload.put("stage", "query_done");
                payload.put("platform", "android");
                payload.put("bundleId", bundleId);
                payload.put("responseCode", BillingClient.BillingResponseCode.OK);
                payload.put("responseName", codeName(BillingClient.BillingResponseCode.OK));
                payload.put("productCount", lastProductCount);
                payload.put("prices", prices);
                payload.put("validProductIds", new JSONArray(validIds()));
                payload.put("unfetchedProductIds", new JSONArray(lastUnfetched));
                if (!lastUnfetched.isEmpty()) {
                    payload.put("message", "unfetched product ids");
                }
                emit(payload.toString());
            } catch (Exception e) {
                emit(report("query_done", -1, e.getMessage(), requestedIds(), new ArrayList<>(), lastProductCount));
            }
        });
    }

    private void queryDetailsThen(Runnable next) {
        if (client == null || !client.isReady()) {
            Log.w(TAG, "Play Billing is not connected; product query skipped");
            emit(report("connecting", -1, "BillingClient is not connected", requestedIds(), new ArrayList<>(), 0));
            return;
        }
        emitProgress("querying", "queryProductDetailsAsync");
        Log.i(TAG, "Play Billing connected; querying INAPP " + CREDIT + ", " + UNLIMITED);
        List<QueryProductDetailsParams.Product> list = new ArrayList<>();
        list.add(product(CREDIT));
        list.add(product(UNLIMITED));
        QueryProductDetailsParams params = QueryProductDetailsParams.newBuilder().setProductList(list).build();
        client.queryProductDetailsAsync(params, (BillingResult result, QueryProductDetailsResult queryResult) -> {
            logResult("queryProductDetails", result);
            lastUnfetched.clear();
            lastUnfetched.addAll(unfetchedIds(queryResult));
            List<ProductDetails> details = queryResult == null ? null : queryResult.getProductDetailsList();
            lastProductCount = details == null ? 0 : details.size();
            if (result.getResponseCode() != BillingClient.BillingResponseCode.OK || details == null) {
                List<String> ids = lastUnfetched.isEmpty() ? requestedIds() : lastUnfetched;
                String message = debugOf(result);
                if (result.getResponseCode() == BillingClient.BillingResponseCode.OK && lastProductCount == 0) {
                    message = "query returned 0 products with OK";
                }
                emit(report("query_done", result.getResponseCode(), message, ids, new ArrayList<>(), lastProductCount));
                return;
            }
            products.clear();
            for (ProductDetails item : details) {
                products.put(item.getProductId(), item);
            }
            next.run();
        });
    }

    private void launch(Activity activity, String productId) {
        ProductDetails details = products.get(productId);
        if (details == null) {
            emit(report("query_done", BillingClient.BillingResponseCode.ITEM_UNAVAILABLE, "product was not returned", requestedIds(), validIds(), lastProductCount));
            return;
        }
        ProductDetails.OneTimePurchaseOfferDetails offer = offerOf(details);
        if (offer == null) {
            emit(report("query_done", BillingClient.BillingResponseCode.ITEM_UNAVAILABLE, "product has no purchase offer", Collections.singletonList(productId), validIds(), lastProductCount));
            return;
        }
        BillingFlowParams.ProductDetailsParams item = BillingFlowParams.ProductDetailsParams.newBuilder()
                .setProductDetails(details)
                .setOfferToken(offer.getOfferToken())
                .build();
        BillingFlowParams flow = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(Collections.singletonList(item))
                .build();
        BillingResult result = client.launchBillingFlow(activity, flow);
        if (result.getResponseCode() != BillingClient.BillingResponseCode.OK) {
            logResult("launchBillingFlow", result);
            emit(report("connected", result.getResponseCode(), debugOf(result), Collections.singletonList(productId), validIds(), lastProductCount));
        }
    }

    @Override
    public void onPurchasesUpdated(BillingResult result, List<Purchase> purchases) {
        int code = result.getResponseCode();
        logResult("onPurchasesUpdated", result);
        if (code == BillingClient.BillingResponseCode.USER_CANCELED) {
            emit(reportCancelled(result));
            return;
        }
        if (code != BillingClient.BillingResponseCode.OK || purchases == null || purchases.isEmpty()) {
            emit(report("connected", code, debugOf(result), requestedIds(), validIds(), purchases == null ? 0 : purchases.size()));
            return;
        }
        for (Purchase purchase : purchases) {
            if (purchase.getPurchaseState() == Purchase.PurchaseState.PURCHASED) {
                emit(purchaseJson(purchase).toString());
                return;
            }
        }
        emit(status("error"));
    }

    private void settle(Purchase purchase) {
        String token = purchase.getPurchaseToken();
        boolean credit = purchase.getProducts().contains(CREDIT);
        if (credit) {
            client.consumeAsync(ConsumeParams.newBuilder().setPurchaseToken(token).build(), (result, out) -> emit(status("ok")));
        } else {
            client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(token).build(), result -> emit(status("ok")));
        }
    }

    private static int visibleBillingServices(Activity activity) {
        Intent service = new Intent(BILLING_ACTION);
        service.setPackage("com.android.vending");
        PackageManager packages = activity.getPackageManager();
        List<ResolveInfo> matches = packages.queryIntentServices(service, 0);
        int count = matches == null ? 0 : matches.size();
        if (matches != null) {
            for (ResolveInfo info : matches) {
                if (info == null || info.serviceInfo == null) {
                    continue;
                }
                Log.i(TAG, "billing service " + info.serviceInfo.packageName + "/" + info.serviceInfo.name);
            }
        }
        return count;
    }

    private static QueryProductDetailsParams.Product product(String id) {
        return QueryProductDetailsParams.Product.newBuilder()
                .setProductId(id)
                .setProductType(BillingClient.ProductType.INAPP)
                .build();
    }

    /** The store's localized price and the offer token used to buy it. */
    private static ProductDetails.OneTimePurchaseOfferDetails offerOf(ProductDetails details) {
        List<ProductDetails.OneTimePurchaseOfferDetails> offers = details.getOneTimePurchaseOfferDetailsList();
        if (offers == null) {
            return null;
        }
        for (ProductDetails.OneTimePurchaseOfferDetails offer : offers) {
            if (offer == null || offer.getOfferToken() == null || offer.getOfferToken().isEmpty()) {
                continue;
            }
            if (offer.getFormattedPrice() != null && !offer.getFormattedPrice().isEmpty()) {
                return offer;
            }
        }
        return null;
    }

    private static String priceOf(ProductDetails details) {
        ProductDetails.OneTimePurchaseOfferDetails offer = offerOf(details);
        return offer == null ? "" : offer.getFormattedPrice();
    }

    private static JSONObject purchaseJson(Purchase purchase) {
        JSONObject row = new JSONObject();
        try {
            String productId = purchase.getProducts().isEmpty() ? "" : purchase.getProducts().get(0);
            row.put("status", "ok");
            row.put("platform", "android");
            row.put("productId", productId);
            row.put("purchaseToken", purchase.getPurchaseToken());
            row.put("transactionId", purchase.getOrderId() == null ? purchase.getPurchaseToken() : purchase.getOrderId());
            row.put("revoked", purchase.getPurchaseState() != Purchase.PurchaseState.PURCHASED);
        } catch (Exception ignored) {
            // A missing field still leaves a JSON object the client can reject.
        }
        return row;
    }

    private static List<String> requestedIds() {
        List<String> ids = new ArrayList<>();
        ids.add(CREDIT);
        ids.add(UNLIMITED);
        return ids;
    }

    private static List<String> unfetchedIds(QueryProductDetailsResult queryResult) {
        List<String> ids = new ArrayList<>();
        if (queryResult == null || queryResult.getUnfetchedProductList() == null) {
            return ids;
        }
        for (UnfetchedProduct item : queryResult.getUnfetchedProductList()) {
            if (item == null) {
                continue;
            }
            String id = item.getProductId() == null ? "" : item.getProductId();
            Log.w(TAG, "unfetched productId=" + id + " statusCode=" + item.getStatusCode());
            if (!id.isEmpty()) {
                ids.add(id);
            }
        }
        return ids;
    }

    private void emitProgress(String stage, String message) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("status", "progress");
            payload.put("stage", stage);
            payload.put("platform", "android");
            payload.put("bundleId", bundleId);
            payload.put("message", message == null ? "" : message);
            payload.put("productIds", new JSONArray(requestedIds()));
            emit(payload.toString());
        } catch (Exception e) {
            Log.w(TAG, "progress " + e.getMessage());
        }
    }

    private static String debugOf(BillingResult result) {
        if (result == null) {
            return "null BillingResult";
        }
        String message = result.getDebugMessage();
        return message == null ? "" : message;
    }

    private static String codeName(int code) {
        switch (code) {
            case BillingClient.BillingResponseCode.OK:
                return "OK";
            case BillingClient.BillingResponseCode.USER_CANCELED:
                return "USER_CANCELED";
            case BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE:
                return "SERVICE_UNAVAILABLE";
            case BillingClient.BillingResponseCode.BILLING_UNAVAILABLE:
                return "BILLING_UNAVAILABLE";
            case BillingClient.BillingResponseCode.ITEM_UNAVAILABLE:
                return "ITEM_UNAVAILABLE";
            case BillingClient.BillingResponseCode.DEVELOPER_ERROR:
                return "DEVELOPER_ERROR";
            case BillingClient.BillingResponseCode.ERROR:
                return "ERROR";
            case BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED:
                return "ITEM_ALREADY_OWNED";
            case BillingClient.BillingResponseCode.ITEM_NOT_OWNED:
                return "ITEM_NOT_OWNED";
            case BillingClient.BillingResponseCode.NETWORK_ERROR:
                return "NETWORK_ERROR";
            case BillingClient.BillingResponseCode.SERVICE_DISCONNECTED:
                return "SERVICE_DISCONNECTED";
            default:
                return "UNKNOWN";
        }
    }

    private String reportCancelled(BillingResult result) {
        try {
            JSONObject payload = new JSONObject(report("connected", result.getResponseCode(), debugOf(result), requestedIds(), validIds(), 0));
            payload.put("status", "cancelled");
            return payload.toString();
        } catch (Exception e) {
            return status("cancelled");
        }
    }

    private static void logResult(String where, BillingResult result) {
        int code = result == null ? -1 : result.getResponseCode();
        String message = result == null ? "null BillingResult" : String.valueOf(result.getDebugMessage());
        Log.i(TAG, where + " responseCode=" + code + " debugMessage=" + message);
    }

    private List<String> validIds() {
        return new ArrayList<>(products.keySet());
    }

    private String report(String stage, int code, String message, List<String> invalidIds, List<String> validIds, int productCount) {
        try {
            JSONObject payload = new JSONObject();
            payload.put("status", "unavailable");
            payload.put("stage", stage);
            payload.put("platform", "android");
            payload.put("bundleId", bundleId);
            payload.put("responseCode", code);
            payload.put("responseName", codeName(code));
            payload.put("message", message == null ? "" : message);
            payload.put("productCount", productCount);
            payload.put("productIds", new JSONArray(invalidIds == null ? requestedIds() : invalidIds));
            payload.put("unfetchedProductIds", new JSONArray(invalidIds == null ? requestedIds() : invalidIds));
            payload.put("validProductIds", new JSONArray(validIds == null ? new ArrayList<>() : validIds));
            return payload.toString();
        } catch (Exception e) {
            return status("unavailable");
        }
    }

    private static String status(String value) {
        return "{\"status\":\"" + value + "\"}";
    }

    private void emit(String json) {
        Log.i(TAG, json);
        listener.onBilling(json);
    }
}
