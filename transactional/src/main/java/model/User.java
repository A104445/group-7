package model;

import java.time.LocalDateTime;
import java.util.List;

public record User(
    String username,
    LocalDateTime createdAt,
    String bio,
    List<Repository> repositories
) {
}
