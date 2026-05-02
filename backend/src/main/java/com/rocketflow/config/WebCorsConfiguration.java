package com.rocketflow.config;

import java.util.List;
import java.util.stream.Collectors;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

@Configuration
public class WebCorsConfiguration {

    @Bean
    CorsConfigurationSource corsConfigurationSource(WebCorsProperties properties) {
        CorsConfiguration configuration = new CorsConfiguration();
        List<String> allowedOrigins = properties.getAllowedOrigins().stream()
                .filter(origin -> origin != null && !origin.isBlank())
                .collect(Collectors.toList());

        if (!allowedOrigins.isEmpty()) {
            configuration.setAllowedOrigins(allowedOrigins);
        }

        List<String> allowedOriginPatterns = properties.getAllowedOriginPatterns().stream()
                .filter(origin -> origin != null && !origin.isBlank())
                .collect(Collectors.toList());

        if (!allowedOriginPatterns.isEmpty()) {
            configuration.setAllowedOriginPatterns(allowedOriginPatterns);
        }

        configuration.setAllowedMethods(properties.getAllowedMethods());
        configuration.setAllowedHeaders(properties.getAllowedHeaders());
        configuration.setExposedHeaders(properties.getExposedHeaders());
        configuration.setAllowCredentials(false);
        configuration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", configuration);
        return source;
    }
}
