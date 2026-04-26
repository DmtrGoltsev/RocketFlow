package com.rocketflow.auth;

import java.io.IOException;
import java.time.Instant;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component
public class TokenAuthenticationFilter extends OncePerRequestFilter {

    private final AuthSessionRepository authSessionRepository;
    private final TokenHasher tokenHasher;
    private final UserRepository userRepository;

    public TokenAuthenticationFilter(
            AuthSessionRepository authSessionRepository,
            TokenHasher tokenHasher,
            UserRepository userRepository
    ) {
        this.authSessionRepository = authSessionRepository;
        this.tokenHasher = tokenHasher;
        this.userRepository = userRepository;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String authorization = request.getHeader("Authorization");
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        String token = authorization.substring("Bearer ".length()).trim();
        authSessionRepository.findByAccessTokenHashAndRevokedAtIsNull(tokenHasher.hash(token))
                .filter(session -> session.getAccessExpiresAt().isAfter(Instant.now()))
                .flatMap(session -> userRepository.findById(session.getUserId()))
                .filter(User::isActive)
                .ifPresent(user -> authenticate(request, user));

        filterChain.doFilter(request, response);
    }

    private void authenticate(HttpServletRequest request, User user) {
        if (SecurityContextHolder.getContext().getAuthentication() != null) {
            return;
        }

        AuthenticatedUser principal = new AuthenticatedUser(user.getId(), user.getEmail());
        UsernamePasswordAuthenticationToken authentication =
                new UsernamePasswordAuthenticationToken(principal, null, java.util.List.of());
        authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
        SecurityContextHolder.getContext().setAuthentication(authentication);
    }
}
