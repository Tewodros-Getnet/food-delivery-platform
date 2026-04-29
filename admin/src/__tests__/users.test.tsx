/**
 * Admin Users Page Tests
 * Tests search, role filter, suspend/reactivate, pagination, verified badge.
 */
import React from 'react';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom';

jest.mock('@/lib/api', () => ({
  api: {
    get: jest.fn(),
    put: jest.fn(),
  },
}));

import { api } from '@/lib/api';
const mockApi = api as jest.Mocked<typeof api>;

import UsersPage from '@/app/dashboard/users/page';

const mockUsers = [
  {
    id: 'user-1',
    email: 'customer@test.com',
    role: 'customer',
    display_name: 'Alice Customer',
    status: 'active',
    email_verified: true,
    created_at: '2024-01-01T00:00:00Z',
    order_count: '15',
  },
  {
    id: 'user-2',
    email: 'rider@test.com',
    role: 'rider',
    display_name: 'Bob Rider',
    status: 'suspended',
    email_verified: false,
    created_at: '2024-01-02T00:00:00Z',
    order_count: '42',
  },
];

const mockPagination = { page: 1, limit: 20, total: 2, pages: 1 };

describe('UsersPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders user list', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Alice Customer')).toBeInTheDocument();
    });

    expect(screen.getByText('Bob Rider')).toBeInTheDocument();
  });

  it('shows total user count', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: { ...mockPagination, total: 150 } } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('150 total users')).toBeInTheDocument();
    });
  });

  it('shows Verified badge for verified users', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Verified')).toBeInTheDocument();
    });
  });

  it('shows Pending badge for unverified users', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Pending')).toBeInTheDocument();
    });
  });

  it('shows Suspend button for active users', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Alice Customer')).toBeInTheDocument();
    });

    expect(screen.getByText('Suspend')).toBeInTheDocument();
  });

  it('shows Reactivate button for suspended users', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Bob Rider')).toBeInTheDocument();
    });

    expect(screen.getByText('Reactivate')).toBeInTheDocument();
  });

  it('calls suspend endpoint when Suspend clicked', async () => {
    mockApi.get.mockResolvedValue({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });
    mockApi.put.mockResolvedValueOnce({ data: { success: true } });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Suspend')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Suspend'));

    await waitFor(() => {
      expect(mockApi.put).toHaveBeenCalledWith('/admin/users/user-1/suspend');
    });
  });

  it('calls reactivate endpoint when Reactivate clicked', async () => {
    mockApi.get.mockResolvedValue({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });
    mockApi.put.mockResolvedValueOnce({ data: { success: true } });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Reactivate')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Reactivate'));

    await waitFor(() => {
      expect(mockApi.put).toHaveBeenCalledWith('/admin/users/user-2/reactivate');
    });
  });

  it('shows role badges with correct styles', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('customer')).toBeInTheDocument();
    });

    expect(screen.getByText('rider')).toBeInTheDocument();
  });

  it('shows empty state when no users found', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { users: [], pagination: { ...mockPagination, total: 0 } } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('No users found')).toBeInTheDocument();
    });
  });

  it('calls API with search param when Search clicked', async () => {
    mockApi.get.mockResolvedValue({
      data: { data: { users: mockUsers, pagination: mockPagination } },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByPlaceholderText('Search by email or name...')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByPlaceholderText('Search by email or name...'), {
      target: { value: 'alice' },
    });
    fireEvent.click(screen.getByText('Search'));

    await waitFor(() => {
      expect(mockApi.get).toHaveBeenCalledWith(
        '/admin/users',
        expect.objectContaining({
          params: expect.objectContaining({ search: 'alice' }),
        })
      );
    });
  });

  it('shows pagination when multiple pages', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: {
        data: {
          users: mockUsers,
          pagination: { page: 1, limit: 20, total: 100, pages: 5 },
        },
      },
    });

    render(<UsersPage />);

    await waitFor(() => {
      expect(screen.getByText('Showing 1–2 of 100')).toBeInTheDocument();
    });

    expect(screen.getByText('Next →')).toBeInTheDocument();
  });
});
