/**
 * Admin Restaurants Page Tests
 * Tests approve/reject/suspend/reactivate actions and status display.
 */
import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom';

jest.mock('@/lib/api', () => ({
  api: {
    get: jest.fn(),
    post: jest.fn(),
    put: jest.fn(),
  },
}));

import { api } from '@/lib/api';
const mockApi = api as jest.Mocked<typeof api>;

import RestaurantsPage from '@/app/dashboard/restaurants/page';

const mockRestaurants = [
  {
    id: 'rest-1',
    name: 'Burger Palace',
    owner_email: 'owner1@test.com',
    owner_name: 'Alice',
    status: 'pending',
    menu_count: '12',
    average_rating: 4.5,
  },
  {
    id: 'rest-2',
    name: 'Pizza Hub',
    owner_email: 'owner2@test.com',
    owner_name: 'Bob',
    status: 'approved',
    menu_count: '8',
    average_rating: 4.2,
  },
  {
    id: 'rest-3',
    name: 'Sushi Place',
    owner_email: 'owner3@test.com',
    owner_name: 'Carol',
    status: 'suspended',
    menu_count: '15',
    average_rating: 3.8,
  },
];

describe('RestaurantsPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders restaurant list', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockRestaurants } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Burger Palace')).toBeInTheDocument();
    });

    expect(screen.getByText('Pizza Hub')).toBeInTheDocument();
    expect(screen.getByText('Sushi Place')).toBeInTheDocument();
  });

  it('shows pending count in header', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockRestaurants } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText(/1 pending approval/)).toBeInTheDocument();
    });
  });

  it('shows Approve and Reject buttons for pending restaurants', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockRestaurants } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Burger Palace')).toBeInTheDocument();
    });

    expect(screen.getByText('Approve')).toBeInTheDocument();
    expect(screen.getByText('Reject')).toBeInTheDocument();
  });

  it('shows Suspend button for approved restaurants', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockRestaurants } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Pizza Hub')).toBeInTheDocument();
    });

    expect(screen.getByText('Suspend')).toBeInTheDocument();
  });

  it('shows Reactivate button for suspended restaurants', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockRestaurants } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Sushi Place')).toBeInTheDocument();
    });

    expect(screen.getByText('Reactivate')).toBeInTheDocument();
  });

  it('calls approve endpoint when Approve clicked', async () => {
    mockApi.get.mockResolvedValue({ data: { data: mockRestaurants } });
    mockApi.post.mockResolvedValueOnce({ data: { success: true } });

    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Approve')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Approve'));

    await waitFor(() => {
      expect(mockApi.post).toHaveBeenCalledWith('/restaurants/rest-1/approve');
    });
  });

  it('calls reject endpoint when Reject clicked', async () => {
    mockApi.get.mockResolvedValue({ data: { data: mockRestaurants } });
    mockApi.post.mockResolvedValueOnce({ data: { success: true } });

    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Reject')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Reject'));

    await waitFor(() => {
      expect(mockApi.post).toHaveBeenCalledWith('/restaurants/rest-1/reject');
    });
  });

  it('calls suspend endpoint when Suspend clicked', async () => {
    mockApi.get.mockResolvedValue({ data: { data: mockRestaurants } });
    mockApi.put.mockResolvedValueOnce({ data: { success: true } });

    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Suspend')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Suspend'));

    await waitFor(() => {
      expect(mockApi.put).toHaveBeenCalledWith('/restaurants/rest-2/suspend');
    });
  });

  it('calls unsuspend endpoint when Reactivate clicked', async () => {
    mockApi.get.mockResolvedValue({ data: { data: mockRestaurants } });
    mockApi.put.mockResolvedValueOnce({ data: { success: true } });

    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('Reactivate')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Reactivate'));

    await waitFor(() => {
      expect(mockApi.put).toHaveBeenCalledWith('/admin/restaurants/rest-3/unsuspend');
    });
  });

  it('shows empty state when no restaurants', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: [] } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('No restaurants found')).toBeInTheDocument();
    });
  });

  it('shows menu item count', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockRestaurants } });
    render(<RestaurantsPage />);

    await waitFor(() => {
      expect(screen.getByText('12 items')).toBeInTheDocument();
    });
  });
});
