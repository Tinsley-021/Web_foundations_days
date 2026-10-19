# SnapShare — System Scaling Plan

## Project Overview

SnapShare is a photo-sharing application designed to support 10 million registered users. This project presents a system design and scaling plan for handling photo uploads, feed requests, media storage, and background image processing.

The design focuses on performance, reliability, scalability, and cost efficiency.

## Business and Traffic Assumptions

- Registered users: 10,000,000
- Daily active users: 10% (1,000,000 users)
- Photo uploads: 1 photo per active user per day
- Feed views: 50 feed pages per active user per day
- Original photo size: 2 MB
- Thumbnail size: 50 KB
- Average day: 86,400 seconds
- Peak traffic: 5 times the average rate

## Key Capacity Estimates

| Metric | Average | Peak |
|---|---:|---:|
| Photo uploads | 11.57/second | 57.87/second |
| Feed views | 578.70/second | 2,893.52/second |

Estimated media storage:

- Daily storage: 2.05 TB
- Annual storage: 748.25 TB

These storage estimates exclude replication, backups, metadata, and additional generated image sizes.

## Architecture Overview

The proposed architecture includes:

- **Load balancer:** Distributes API requests across healthy application servers.
- **Application servers:** Handle authentication, uploads, feed requests, and metadata operations.
- **Object storage:** Stores original photos and generated thumbnails.
- **Content Delivery Network (CDN):** Delivers media efficiently to users.
- **Redis cache:** Reduces repeated database queries for frequently requested feeds.
- **Primary database:** Stores users, relationships, photo metadata, and processing status.
- **Read replicas:** Distribute suitable read queries.
- **Job queue:** Schedules background image-processing tasks.
- **Thumbnail workers:** Generate and store thumbnails asynchronously.

## Key Design Decisions

### 1. Separate Media from Metadata

Photos are stored in object storage instead of relational database tables. The database holds metadata and object references, reducing database storage pressure and simplifying media delivery.

### 2. Optimize Read Traffic

SnapShare is read-heavy, with approximately 50 feed views for every photo upload. CDN delivery, feed caching, and database read replicas help handle this workload.

### 3. Process Thumbnails Asynchronously

The application confirms an upload after the original photo and metadata have been safely persisted and the processing job has been reliably scheduled. Thumbnail generation continues in the background.

### 4. Design for Failure Recovery

Workers should retry failed jobs, process duplicate jobs safely, and report persistent failures. Monitoring, queue recovery, and cleanup of orphaned media help maintain reliability.

## Trade-Offs

- **Caching vs. freshness:** Cached feeds improve performance but can temporarily display outdated content.
- **Fast uploads vs. immediate processing:** Background thumbnail generation speeds up upload confirmation but may delay thumbnail availability.
- **Performance vs. cost:** Object storage and CDN delivery improve scalability but introduce storage and data-transfer expenses.

## Detailed Documentation

See [`day7/photo-app-scaling.md`](day7/photo-app-scaling.md) for the complete scaling plan, including capacity calculations, architecture diagram, component descriptions, upload lifecycle, failure handling, and trade-off analysis.

## Conclusion

SnapShare's design separates large media files from structured application data and uses caching, a CDN, read replicas, and asynchronous workers to scale efficiently.

The proposed architecture provides a foundation for supporting growing traffic while balancing performance, reliability, and operating costs.
