import { Router } from 'express';
import authRouter from './auth';
import usersRouter from './users';
import restaurantsRouter from './restaurants';
import menuRouter, { menuRouter as menuItemRouter } from './menu';
import ordersRouter from './orders';
import paymentsRouter from './payments';
import ridersRouter from './riders';
import deliveriesRouter from './deliveries';
import disputesRouter from './disputes';
import adminRouter from './admin';
import searchRouter from './search';

import chatRouter from './chat';

const router = Router();

router.use('/auth', authRouter);
router.use('/users', usersRouter);
router.use('/restaurants', restaurantsRouter);
router.use('/restaurants/:restaurantId/menu', menuRouter);
router.use('/menu', menuItemRouter);
router.use('/orders', ordersRouter);
router.use('/payments', paymentsRouter);
router.use('/riders', ridersRouter);
router.use('/deliveries', deliveriesRouter);
router.use('/disputes', disputesRouter);
router.use('/admin', adminRouter);
router.use('/search', searchRouter);
router.use('/chat', chatRouter);

export default router;
