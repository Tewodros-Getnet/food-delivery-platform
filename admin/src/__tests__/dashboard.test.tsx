/**
 * Admin Analytics Dashboard Tests
 * Tests KPI rendering, chart data, and error/loading states.
 */
import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';

// Mock the api module
jest.mock('@/lib/api', () => ({
  api: {
    get: jest.fn(),
  },
}));

import { api } from '@/lib/api';
const mockApi = api as jest.Mocked<typeof api>;

// Mock recharts to avoid canvas errors in jsdom
jest.mock('recharts', () => ({
  BarChart: ({ children }: { children: React.ReactNode }) => <div data-testid="bar-chart">{children}</div>,
  Bar: () => <div />,
  XAxis: () => <div />,
  YAxis: () => <div />,
  Tooltip: () => <div />,
  ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  PieChart: ({ children }: { children: React.ReactNode }) => <div data-testid="pie-chart">{children}</div>,
  Pie: () => <div />,
  Cell: () => <div />,
  Legend: () => <div />,
}));

import AnalyticsPage from '@/app/dashboard/page';

const mockAnalytics = {
  totalOrders: 1234,
  totalRevenue: 98765.50,
  activeUsers: 456,
  refundFailedCount: 3,
  ordersByStatus: [
    { status: 'delivered', count: '800' },
    { status: 'cancelled', count: '100' },
  ],
  topRestaurants: [
    { id: '1', name: 'Burger Palace', order_count: '200' },
    { id: '2', name: 'Pizza Hub', order_count: '150' },
  ],
  topRiders: [
    { id: '1', display_name: 'John Rider', delivery_count: '50' },
  ],
  dateRange: { start: '2024-01-01', end: '2024-01-31' },
};

describe('AnalyticsPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('shows loading skeleton initially', () => {
    mockApi.get.mockReturnValue(new Promise(() => {})); // never resolves
    render(<AnalyticsPage />);
    // Skeleton has animate-pulse divs
    const skeletons = document.querySelectorAll('.animate-pulse');
    expect(skeletons.length).toBeGreaterThan(0);
  });

  it('renders KPI cards with correct values', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockAnalytics } });
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText('1,234')).toBeInTheDocument();
    });

    expect(screen.getByText(/98,765/)).toBeInTheDocument();
    expect(screen.getByText('456')).toBeInTheDocument();
  });

  it('shows refund failed alert when count > 0', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockAnalytics } });
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText(/3 orders? have failed refunds/i)).toBeInTheDocument();
    });
  });

  it('does not show refund alert when count is 0', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { ...mockAnalytics, refundFailedCount: 0 } },
    });
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText('1,234')).toBeInTheDocument();
    });

    expect(screen.queryByText(/failed refunds/i)).not.toBeInTheDocument();
  });

  it('renders top riders table', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockAnalytics } });
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText('John Rider')).toBeInTheDocument();
    });

    expect(screen.getByText('50 deliveries')).toBeInTheDocument();
  });

  it('shows empty state for top riders when none exist', async () => {
    mockApi.get.mockResolvedValueOnce({
      data: { data: { ...mockAnalytics, topRiders: [] } },
    });
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText('No data yet')).toBeInTheDocument();
    });
  });

  it('shows error state when API fails', async () => {
    mockApi.get.mockRejectedValueOnce(new Error('Network error'));
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText('Failed to load analytics')).toBeInTheDocument();
    });
  });

  it('renders date range picker inputs', async () => {
    mockApi.get.mockResolvedValueOnce({ data: { data: mockAnalytics } });
    render(<AnalyticsPage />);

    await waitFor(() => {
      expect(screen.getByText('1,234')).toBeInTheDocument();
    });

    const dateInputs = document.querySelectorAll('input[type="date"]');
    expect(dateInputs).toHaveLength(2);
  });
});
