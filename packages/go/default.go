package freeproxy

import "context"

var defaultClient, defaultClientErr = NewClient(ClientOptions{})

// GetProxies retrieves matching proxies using the default API client.
func GetProxies(ctx context.Context, filters Filters) ([]Proxy, error) {
	if defaultClientErr != nil {
		return nil, defaultClientErr
	}
	return defaultClient.GetProxies(ctx, filters)
}

// PickBest returns top-ranked proxies using the default API client.
func PickBest(ctx context.Context, n int, filters Filters) ([]Proxy, error) {
	if defaultClientErr != nil {
		return nil, defaultClientErr
	}
	return defaultClient.PickBest(ctx, n, filters)
}

// Rotate creates a rotator using the default API client.
func Rotate(ctx context.Context, filters Filters) (*Rotator, error) {
	if defaultClientErr != nil {
		return nil, defaultClientErr
	}
	return defaultClient.Rotate(ctx, filters)
}
