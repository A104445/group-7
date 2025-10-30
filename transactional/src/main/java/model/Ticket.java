package model;

import java.time.LocalDateTime;

public record Ticket(
    int repositoryId,
    int ticketId,
    String createdBy,
    String type,
    String status,
    LocalDateTime openedAt,
    LocalDateTime closedAt,
    String title,
    String data
) {
}
