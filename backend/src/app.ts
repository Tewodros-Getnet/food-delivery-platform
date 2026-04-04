import express from 'express';
import cors from 'cors';
import { requestIdMiddleware } from './middleware/requestId';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import router from './routes/index';

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(requestIdMiddleware);

app.get('/health', (_req, res) => {
  res.json({ success: true, data: { status: 'ok' }, error: null });
});

app.use('/api/v1', router);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
