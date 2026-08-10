package com.rocketflow.focusnotifications;

import java.net.IDN;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.util.Arrays;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

import com.rocketflow.common.ApiException;

@Component
class WebPushEndpointValidator {
    interface DnsResolver {
        InetAddress[] resolve(String host) throws UnknownHostException;
    }

    private final DnsResolver resolver;
    private final Set<String> allowedHostSuffixes;

    @Autowired
    WebPushEndpointValidator(FocusNotificationProperties properties) {
        this(InetAddress::getAllByName, properties.getWebPush().getAllowedHostSuffixes());
    }

    WebPushEndpointValidator(DnsResolver resolver) {
        this(resolver, Set.of(
                "fcm.googleapis.com",
                "push.services.mozilla.com",
                "notify.windows.com",
                "push.apple.com"
        ));
    }

    WebPushEndpointValidator(DnsResolver resolver, Set<String> allowedHostSuffixes) {
        this.resolver = resolver;
        this.allowedHostSuffixes = allowedHostSuffixes.stream()
                .map(this::normalizeHost)
                .collect(Collectors.toUnmodifiableSet());
    }

    URI requirePublicHttps(String endpoint) {
        URI uri;
        try {
            uri = URI.create(endpoint);
        } catch (IllegalArgumentException exception) {
            throw invalidEndpoint();
        }
        String host = uri.getHost();
        if (!"https".equalsIgnoreCase(uri.getScheme()) || host == null || host.isBlank()
                || uri.getUserInfo() != null || uri.getFragment() != null
                || (uri.getPort() != -1 && uri.getPort() != 443)) {
            throw invalidEndpoint();
        }
        String normalizedHost;
        try {
            normalizedHost = normalizeHost(host);
        } catch (IllegalArgumentException exception) {
            throw invalidEndpoint();
        }
        if (!isAllowedProviderHost(normalizedHost)) {
            throw invalidEndpoint();
        }
        try {
            InetAddress[] addresses = resolver.resolve(normalizedHost);
            if (addresses.length == 0 || Arrays.stream(addresses).anyMatch(this::isNonGlobal)) {
                throw invalidEndpoint();
            }
        } catch (UnknownHostException exception) {
            throw invalidEndpoint();
        }
        return uri;
    }

    private boolean isAllowedProviderHost(String host) {
        return allowedHostSuffixes.stream()
                .anyMatch(suffix -> host.equals(suffix) || host.endsWith("." + suffix));
    }

    private String normalizeHost(String host) {
        String normalized = host.strip().toLowerCase(Locale.ROOT);
        if (normalized.endsWith(".")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return IDN.toASCII(normalized, IDN.USE_STD3_ASCII_RULES).toLowerCase(Locale.ROOT);
    }

    private boolean isNonGlobal(InetAddress address) {
        if (address.isAnyLocalAddress() || address.isLoopbackAddress() || address.isLinkLocalAddress()
                || address.isSiteLocalAddress() || address.isMulticastAddress()) {
            return true;
        }
        byte[] bytes = address.getAddress();
        return address instanceof Inet4Address ? isNonGlobalIpv4(bytes) : isNonGlobalIpv6(bytes);
    }

    private boolean isNonGlobalIpv4(byte[] bytes) {
        int a = unsigned(bytes[0]);
        int b = unsigned(bytes[1]);
        int c = unsigned(bytes[2]);
        return a == 0
                || a == 10
                || a == 127
                || (a == 100 && b >= 64 && b <= 127)
                || (a == 169 && b == 254)
                || (a == 172 && b >= 16 && b <= 31)
                || (a == 192 && b == 0 && c == 0)
                || (a == 192 && b == 0 && c == 2)
                || (a == 192 && b == 88 && c == 99)
                || (a == 192 && b == 168)
                || (a == 198 && (b == 18 || b == 19))
                || (a == 198 && b == 51 && c == 100)
                || (a == 203 && b == 0 && c == 113)
                || a >= 224;
    }

    private boolean isNonGlobalIpv6(byte[] bytes) {
        int first = unsigned(bytes[0]);
        int second = unsigned(bytes[1]);
        boolean globalUnicast = (first & 0xe0) == 0x20;
        return !globalUnicast
                || (first == 0x20 && second == 0x01 && unsigned(bytes[2]) == 0x0d && unsigned(bytes[3]) == 0xb8)
                || (first == 0x20 && second == 0x01 && unsigned(bytes[2]) == 0x00
                    && (unsigned(bytes[3]) == 0x02 || (unsigned(bytes[3]) & 0xf0) == 0x10
                    || (unsigned(bytes[3]) & 0xf0) == 0x20))
                || (first == 0x20 && second == 0x02);
    }

    private int unsigned(byte value) {
        return value & 0xff;
    }

    private ApiException invalidEndpoint() {
        return new ApiException(
                HttpStatus.BAD_REQUEST,
                "web_push_endpoint_invalid",
                "The Web Push endpoint must use an approved public HTTPS provider."
        );
    }
}
