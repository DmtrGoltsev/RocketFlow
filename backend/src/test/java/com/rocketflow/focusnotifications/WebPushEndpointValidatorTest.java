package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.InetAddress;
import java.util.Set;

import org.junit.jupiter.api.Test;

import com.rocketflow.common.ApiException;

class WebPushEndpointValidatorTest {
    @Test
    void acceptsApprovedProviderAndExactSubdomainBoundary() throws Exception {
        WebPushEndpointValidator validator = publicResolver();

        assertThat(validator.requirePublicHttps("https://fcm.googleapis.com/subscription").getHost())
                .isEqualTo("fcm.googleapis.com");
        assertThat(validator.requirePublicHttps("https://updates.push.services.mozilla.com/wpush/v2").getHost())
                .isEqualTo("updates.push.services.mozilla.com");
        assertThatThrownBy(() -> validator.requirePublicHttps("https://fcm.googleapis.com.attacker.test/a"))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> validator.requirePublicHttps("https://evilfcm.googleapis.com/a"))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void rejectsUserInfoAndNonStandardPortBeforeResolution() {
        WebPushEndpointValidator validator = new WebPushEndpointValidator(host -> {
            throw new AssertionError("DNS must not be queried");
        });

        assertThatThrownBy(() -> validator.requirePublicHttps("https://user@fcm.googleapis.com/a"))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> validator.requirePublicHttps("https://fcm.googleapis.com:8443/a"))
                .isInstanceOf(ApiException.class);
        assertThatThrownBy(() -> validator.requirePublicHttps("http://fcm.googleapis.com/a"))
                .isInstanceOf(ApiException.class);
    }

    @Test
    void rejectsPrivateCgnatBenchmarkAndDocumentationRanges() throws Exception {
        assertRejectedAddress(new byte[]{10, 0, 0, 8});
        assertRejectedAddress(new byte[]{100, 64, 0, 1});
        assertRejectedAddress(new byte[]{(byte) 198, 18, 0, 1});
        assertRejectedAddress(new byte[]{(byte) 203, 0, 113, 1});
        assertRejectedAddress(InetAddress.getByName("2001:db8::1").getAddress());
    }

    @Test
    void configurableAllowlistStillRequiresPublicDns() throws Exception {
        WebPushEndpointValidator allowed = new WebPushEndpointValidator(
                host -> new InetAddress[]{InetAddress.getByAddress(new byte[]{1, 1, 1, 1})},
                Set.of("push.example.test")
        );

        assertThat(allowed.requirePublicHttps("https://push.example.test/a").getHost())
                .isEqualTo("push.example.test");
        assertThatThrownBy(() -> allowed.requirePublicHttps("https://other.example.test/a"))
                .isInstanceOf(ApiException.class);
    }

    private WebPushEndpointValidator publicResolver() {
        return new WebPushEndpointValidator(host -> new InetAddress[]{
                InetAddress.getByAddress(new byte[]{8, 8, 8, 8})
        });
    }

    private void assertRejectedAddress(byte[] address) throws Exception {
        WebPushEndpointValidator validator = new WebPushEndpointValidator(host -> new InetAddress[]{
                InetAddress.getByAddress(address)
        });
        assertThatThrownBy(() -> validator.requirePublicHttps("https://fcm.googleapis.com/a"))
                .isInstanceOf(ApiException.class);
    }
}
