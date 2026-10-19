# My SnapShare Scaling Plan

## The assumptions and estimates

- Registered users: 10,000,000.
- Daily active users (DAU): 10% of registered users.
- Each active user uploads 1 photo per day and views 50 feed pages per day.
- Each original photo is 2 MB; each thumbnail is 50 KB.
- Use 86,400 seconds per day for the calculations.
- Assume uploads and feed views are spread evenly across the day for average rates; peak traffic is 5× the average.
- Use decimal storage units: 1 MB = 1,000 KB and 1 GB = 1,000 MB. Storage estimates exclude replication, backups, and metadata.

**Daily active users**

10,000,000 × 10% = **1,000,000 DAU**

**Uploads per second**

1,000,000 active users × 1 photo/day = 1,000,000 uploads/day  
1,000,000 ÷ 86,400 ≈ **11.6 uploads/second average**  
11.6 × 5 ≈ **58 uploads/second peak**

**Feed views per second**

1,000,000 active users × 50 feed pages/day = 50,000,000 feed views/day  
50,000,000 ÷ 86,400 ≈ **579 feed views/second average**  
579 × 5 ≈ **2,894 feed views/second peak**

**Photo storage per year**

Each upload stores a 2 MB original plus a 50 KB (0.05 MB) thumbnail:  
1,000,000 photos/day × 2.05 MB = 2,050,000 MB/day  
2,050,000 MB/day × 365 = 748,250,000 MB/year  
= **about 748 TB/year** (decimal units)

This is the storage for one copy of originals and thumbnails, before replication, backups, or growth.

## Read/write profile

SnapShare is **read-heavy**: it has about 50 feed views per upload. The design should serve feed data efficiently with caching, read replicas, and a CDN, while handling photo uploads durably through object storage and background processing.

## Architecture

text
                         ┌──────────────┐
                         │     DNS      │
                         └──────┬───────┘
                                │
             ┌──────────────────┴──────────────────┐
             │                                     │
             v                                     v
┌──────────────────────┐                 ┌────────────────┐
│ Browser / mobile app │──static files──>│ CDN            │
└──────────┬───────────┘                 │ photos, thumbs,│
           │ feed/API requests           │ app assets     │
           v                             └───────▲────────┘
   ┌───────────────┐                             │
   │ Load balancer │                             │ fetch on miss
   └───────┬───────┘                             │
           │                              ┌──────┴─────────┐
      ┌────┴─────┐                        │ Object storage │
      v          v                        │ originals and  │
 ┌────────┐  ┌────────┐                   │ thumbnails     │
 │ App 1  │  │ App 2  │                   └──────▲────────┘
 └──┬──┬──┘  └──┬──┬──┘                          │
    │  │        │  │                      ┌───────┴──────┐
    │  └────────┼──┴──> ┌──────────────┐  │ Thumbnail    │
    │           └──────>│ Cache        │  │ worker       │
    │                   │ feed data    │  └───────▲──────┘
    │                   └──────────────┘          │
    │                                      ┌───────┴──────┐
    ├── writes ──> ┌──────────────┐        │ Job queue    │
    │              │ Primary DB   │        └───────▲──────┘
    │              └──────┬───────┘                │
    │                     │ replication            │
    │                     v                        │
    └── reads ───> ┌──────────────┐                │
                   │ Read replica │                │
                   └──────────────┘       App queues thumbnail job
