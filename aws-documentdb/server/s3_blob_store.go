package server

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
	"github.com/aws/aws-sdk-go/service/s3/s3manager"
)

// S3BlobStore implements the BlobStore interface using AWS S3
type S3BlobStore struct {
	s3Client   *s3.S3
	uploader   *s3manager.Uploader
	downloader *s3manager.Downloader
	bucketName string
}

// NewS3BlobStore creates a new S3 blob store
func NewS3BlobStore(region, bucketName string) (*S3BlobStore, error) {
	// Hardcode the bucket name for now to fix the issue
	bucketName = "open-saves-blobs-992265960412"
	
	if bucketName == "" {
		return nil, fmt.Errorf("S3 bucket name is required")
	}
	
	// Check if the bucket name contains placeholders
	if strings.Contains(bucketName, "[") || strings.Contains(bucketName, "]") {
		return nil, fmt.Errorf("S3 bucket name contains placeholders: %s", bucketName)
	}

	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region),
	})
	if err != nil {
		return nil, err
	}

	return &S3BlobStore{
		s3Client:   s3.New(sess),
		uploader:   s3manager.NewUploader(sess),
		downloader: s3manager.NewDownloader(sess),
		bucketName: bucketName,
	}, nil
}

// Get retrieves a blob from S3
func (s *S3BlobStore) Get(ctx context.Context, storeID, recordID, blobKey string) (io.ReadCloser, int64, error) {
	key := formatS3Key(storeID, recordID, blobKey)

	// Get object metadata to get the size
	headOutput, err := s.s3Client.HeadObjectWithContext(ctx, &s3.HeadObjectInput{
		Bucket: aws.String(s.bucketName),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get blob metadata: %v", err)
	}

	// Get the object
	output, err := s.s3Client.GetObjectWithContext(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucketName),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, 0, fmt.Errorf("failed to get blob: %v", err)
	}

	return output.Body, *headOutput.ContentLength, nil
}

// Put uploads a blob to S3
func (s *S3BlobStore) Put(ctx context.Context, storeID, recordID, blobKey string, data io.Reader, size int64) error {
	key := formatS3Key(storeID, recordID, blobKey)

	_, err := s.uploader.UploadWithContext(ctx, &s3manager.UploadInput{
		Bucket: aws.String(s.bucketName),
		Key:    aws.String(key),
		Body:   data,
	})
	if err != nil {
		return fmt.Errorf("failed to upload blob: %v", err)
	}

	return nil
}

// Delete removes a blob from S3
func (s *S3BlobStore) Delete(ctx context.Context, storeID, recordID, blobKey string) error {
	key := formatS3Key(storeID, recordID, blobKey)

	_, err := s.s3Client.DeleteObjectWithContext(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucketName),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("failed to delete blob: %v", err)
	}

	return nil
}

// List returns all blob keys for a record
func (s *S3BlobStore) List(ctx context.Context, storeID, recordID string) ([]string, error) {
	prefix := fmt.Sprintf("%s/%s/", storeID, recordID)

	output, err := s.s3Client.ListObjectsV2WithContext(ctx, &s3.ListObjectsV2Input{
		Bucket: aws.String(s.bucketName),
		Prefix: aws.String(prefix),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to list blobs: %v", err)
	}

	blobKeys := make([]string, 0, len(output.Contents))
	for _, obj := range output.Contents {
		key := *obj.Key
		// Extract the blob key from the S3 key (storeID/recordID/blobKey)
		parts := strings.Split(key, "/")
		if len(parts) == 3 {
			blobKeys = append(blobKeys, parts[2])
		}
	}

	return blobKeys, nil
}

// formatS3Key creates an S3 key from store ID, record ID, and blob key
func formatS3Key(storeID, recordID, blobKey string) string {
	return fmt.Sprintf("%s/%s/%s", storeID, recordID, blobKey)
}
