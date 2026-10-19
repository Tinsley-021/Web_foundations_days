# SnapShare — Scaling Plan

## 1. Assumptions

- Registered users: 10,000,000.
- Daily active users (DAU): 10% of registered users.
- Each active user uploads one photo per day.
- Each active user views 50 feed pages per day.
- Each original photo is 2 MB.
- Each thumbnail is 50 KB.
- One day contains 86,400 seconds.
- Uploads and feed views are evenly distributed for average-rate calculations.
- Peak traffic is five times the average rate.
- Storage uses decimal units: 1 MB = 1,000 KB and 1 GB = 1,000 MB.
- Storage estimates exclude replication, backups, metadata, and additional generated image sizes.

## 2. Capacity Estimates

### Daily Active Users

10,000,000 registered users × 10% daily activity

**Daily active users = 1,000,000**

### Upload Requests

1,000,000 active users × 1 photo per day = 1,000,000 uploads per day.

Average upload rate:

1,000,000 ÷ 86,400 = approximately 11.57 uploads per second.

Peak upload rate:

11.57 × 5 = approximately 57.87 uploads per second.

**Estimated peak: 58 uploads per second.**

### Feed Views

1,000,000 active users × 50 feed pages per day = 50,000,000 feed views per day.

Average feed-view rate:

50,000,000 ÷ 86,400 = approximately 578.70 feed views per second.

Peak feed-view rate:

578.70 × 5 = approximately 2,893.52 feed views per second.

**Estimated peak: 2,894 feed views per second.**

These estimates represent average and peak request rates. A feed request may trigger several internal operations, so database queries and cache operations must be measured separately during load testing.

### Photo Storage

Each uploaded photo requires storage for its original and thumbnail.

- Original photo: 2 MB.
- Thumbnail: 50 KB = 0.05 MB.
- Total per uploaded photo: 2.05 MB.

Daily storage:

1,000,000 × 2.05 MB = 2,050,000 MB per day.

This equals 2.05 TB per day.

Annual storage:

2,050,000 MB × 365 = 748,250,000 MB per year.

**Estimated annual storage: 748.25 TB**, or approximately 748 TB.

This estimate assumes every original and thumbnail is retained for one year. Actual storage requirements will increase with backups, replication, metadata, additional image sizes, and user growth.

## 3. Read-Heavy or Write-Heavy?

SnapShare is a read-heavy system because users view approximately 50 feed pages for every photo they upload.

The design must efficiently support frequent feed requests while keeping uploads reliable and durable.

The main strategies are:

- Use a CDN to deliver photos and thumbnails close to users.
- Cache frequently requested feed data.
- Use database read replicas to distribute feed-query workloads.
- Store media files separately from structured application data.
- Process thumbnails asynchronously rather than making users wait for image processing.
- Scale application servers horizontally as request traffic grows.

The objective is to keep feed loading fast while ensuring uploaded photos are safely stored and processed.

## 4. Where Should Photos Be Stored?

SnapShare should store original photos and generated thumbnails in object storage, such as Amazon S3, rather than directly in relational database tables.

At approximately 748 TB of new media per year, storing binary files in database tables would substantially increase database size, backup duration, storage costs, and recovery complexity. Large binary objects would also compete with frequently accessed user, follow, and photo-metadata queries for database resources.

Object storage is designed to hold large files durably and expose them through stable object keys or URLs. A CDN can then cache and deliver these files efficiently.

The relational database should store metadata such as:

- Photo ID and owner ID.
- Caption and upload timestamp.
- Original object key or URL.
- Thumbnail object key or URL.
- Processing status, such as `PROCESSING`, `READY`, or `FAILED`.

The database remains responsible for structured data and relationships, while object storage handles the actual image bytes.

The application should use private storage permissions and authorized upload mechanisms where appropriate. Publicly accessible images can be delivered through controlled CDN URLs, while private photos require authorization.

## 5. System Architecture

```text
                       Mobile App / Browser
                                |
                       HTTPS API Requests
                                |
                         Load Balancer
                                |
                 +--------------+--------------+
                 |              |              |
              App 1           App 2           App 3
                 |              |              |
                 +--------------+--------------+
                                |
               +----------------+----------------+
               |                |                |
          Redis Cache       Primary DB       Job Queue
          (feed data)       (metadata)           |
                                |                |
                         Read Replicas      Thumbnail Worker
                                |                |
                         Feed Queries            |
                                                 |
                                              Object
                                              Storage
                                                 |
                                                CDN
                                                 |
                                         Photo Delivery
                                                 |
                                          Mobile App
```

The CDN serves media files from object storage, while application servers handle authenticated API requests and feed-related operations. The queue and worker process thumbnails independently of the user's initial upload request.

## 6. Component Descriptions

### 6.1 Client Application

The browser or mobile application allows users to upload photos, browse feeds, and view thumbnails.

It sends authenticated HTTPS requests to the API and displays upload status. While a thumbnail is processing, the client can show the original image or a placeholder.

### 6.2 DNS

DNS resolves SnapShare's domain name to the appropriate entry point for the application and its CDN.

This allows clients to reach the service without needing to know the underlying server addresses.

### 6.3 Load Balancer

The load balancer distributes incoming API requests across healthy application servers.

It performs health checks and stops directing traffic to failed instances. This improves availability and allows more servers to be added when traffic increases.

### 6.4 Stateless Application Servers

Application servers handle authentication, upload authorization, photo metadata, feed requests, and job creation.

They are stateless so that requests can be served by any healthy instance. This makes horizontal scaling easier during peak traffic.

### 6.5 Object Storage

Object storage holds original photos and generated thumbnails.

It is suitable for large amounts of binary data and can scale independently of the relational database. Each stored file is identified by an object key referenced in the database.

### 6.6 Content Delivery Network (CDN)

The CDN caches and delivers images and thumbnails from locations closer to users.

This reduces image-loading latency, origin traffic, and the amount of media delivery work handled directly by SnapShare's infrastructure.

The CDN should use appropriate cache headers and versioned object keys to prevent stale image content from being served after updates.

### 6.7 Cache

A cache such as Redis stores frequently requested feed data and other suitable temporary results.

This reduces repeated database queries and improves response times. Cache entries should expire or be invalidated when relevant content changes.

The cache is not the permanent source of truth; authoritative data remains in the database.

### 6.8 Primary Database

The primary database stores users, relationships, photo metadata, captions, upload status, and object-storage references.

It handles authoritative writes and maintains the consistency of structured application data.

### 6.9 Read Replicas

Read replicas receive replicated data from the primary database and serve suitable read queries.

They distribute feed-query load and reduce pressure on the primary database. Because replication can lag, recently uploaded photos may not immediately appear in every replica-backed query.

### 6.10 Job Queue

The queue holds background-processing jobs, such as thumbnail generation.

It separates upload handling from slower processing tasks. Jobs can remain queued when workers are busy, allowing processing capacity to be increased independently.

The system should support retries, monitoring, and safe handling of duplicate jobs.

### 6.11 Thumbnail Worker

The thumbnail worker retrieves an original photo, generates a smaller image, stores the thumbnail in object storage, and updates the photo's processing status.

Workers operate independently of API servers. If a worker fails, the queued job can be retried by another worker instead of requiring the user to upload the photo again.

## 7. Step-by-Step Photo Upload Flow

1. The client sends an authenticated upload request to the API through the load balancer.

2. An application server validates the user's permissions, file type, file size, and upload limits.

3. The server stores the original photo in object storage, using a unique object key.

4. After confirming that the original was stored successfully, the application creates a photo metadata record in the primary database with a `PROCESSING` status.

5. The application publishes a thumbnail-generation job to the queue. The job contains the photo ID and the required object key.

6. Once the original and metadata are safely persisted and the job has been durably accepted, the API returns `201 Created` with the photo ID and current processing status. Thumbnail generation does not need to finish before the initial response.

7. A background worker consumes the job, retrieves the original, generates the 50 KB thumbnail, and stores it in object storage.

8. The worker updates the database with the thumbnail reference and changes the processing status to `READY`.

9. The application invalidates or refreshes relevant feed-cache entries so followers can see the new photo.

10. The client can poll the photo-status endpoint or refresh its feed until the photo is ready for normal display.

If the original upload or metadata persistence fails, the API must not report a successful upload. If queue publication fails, the system must retain a recoverable processing task rather than silently leaving the photo permanently stuck.

## 8. Failure Handling and Reliability

### Thumbnail Worker Failure

If a worker crashes while processing a job, the queue should make the unacknowledged job available for retry. Failed jobs should use a bounded retry policy with backoff, followed by a dead-letter queue or equivalent recovery mechanism.

Workers should be idempotent: processing the same photo job more than once must not create inconsistent metadata or corrupt the photo.

### Partial Upload Failure

An object might be stored successfully even if the database write fails. This can leave an orphaned object.

The application should use unique object keys, log failures, and run a cleanup process that identifies unreferenced objects after a safe retention period.

Similarly, if the database record is created but queue publication fails, a transactional outbox or another durable job-publication mechanism can ensure that the thumbnail task is eventually scheduled.

### Database or Cache Problems

If a read replica is unavailable, the application can route eligible reads to another healthy replica or temporarily use the primary within safe capacity limits.

If Redis becomes unavailable, the application should be able to fall back to the database where feasible, with rate limits and capacity safeguards to prevent a sudden overload.

Monitoring should cover request latency, error rates, queue depth, worker failures, database replication lag, cache hit rate, and storage errors.

## 9. Architectural Trade-Offs

### Trade-Off 1: Cache Speed vs. Feed Freshness

**Benefit:** Caching frequently requested feed data reduces database load and improves response times, especially at approximately 2,894 peak feed views per second.

**Cost:** A cached feed can temporarily omit a newly uploaded photo or show outdated information.

**Decision:** Use cache invalidation or targeted refreshes after new uploads. A short period of eventual consistency is acceptable for ordinary social feeds, provided the system eventually displays new content and handles important updates correctly.

### Trade-Off 2: Fast Uploads vs. Immediate Thumbnail Availability

**Benefit:** Asynchronous thumbnail generation allows the API to confirm a successfully persisted upload without waiting for image processing. Workers can scale independently during traffic spikes.

**Cost:** A photo may remain in `PROCESSING` state for a short time, and queue backlogs can delay thumbnail availability.

**Decision:** Return the upload confirmation after durable persistence and reliable job scheduling. Display a placeholder or original image while processing continues, and use retries, monitoring, and idempotent workers to recover from failures.

### Trade-Off 3: Object Storage and CDN Costs vs. Performance

**Benefit:** Object storage provides a scalable home for media, while the CDN reduces latency and repeated requests to the storage origin.

**Cost:** Storage, data transfer, CDN requests, and retained copies all create ongoing expenses.

**Decision:** Use lifecycle policies for eligible older media, monitor storage and delivery costs, and set appropriate cache policies. Apply retention rules without deleting photos that must remain available.

## 10. Conclusion

SnapShare's estimated one million daily active users generate approximately 58 peak uploads per second and 2,894 peak feed views per second. Its media storage requirement is approximately 748 TB per year before replication, backups, and additional overhead.

The scaling strategy separates media delivery from dynamic application requests. Object storage holds photos, the CDN delivers them efficiently, Redis accelerates feed access, database replicas distribute read traffic, and background workers generate thumbnails through a durable queue.

Together with horizontal application scaling, failure recovery, and monitoring, these decisions provide a practical foundation for growing SnapShare while balancing performance, reliability, and operating cost.
