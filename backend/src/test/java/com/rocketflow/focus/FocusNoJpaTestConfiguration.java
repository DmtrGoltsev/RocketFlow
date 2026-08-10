package com.rocketflow.focus;

import static org.mockito.Mockito.mock;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;

@TestConfiguration(proxyBeanMethods = false)
public class FocusNoJpaTestConfiguration {

    @Bean
    FocusPeriodRepository focusPeriodRepository() {
        return mock(FocusPeriodRepository.class);
    }

    @Bean
    FocusItemRepository focusItemRepository() {
        return mock(FocusItemRepository.class);
    }

    @Bean
    FocusNotificationSettingsRepository focusNotificationSettingsRepository() {
        return mock(FocusNotificationSettingsRepository.class);
    }

    @Bean
    FocusCandidateRepository focusCandidateRepository() {
        return mock(FocusCandidateRepository.class);
    }
}
