import React, { useEffect, useState } from "react";

const ORDER_ROUTE = "/orders";

export function OrdersPage(): React.JSX.Element {
  const [orders, setOrders] = useState<string[]>([]);
  useEffect(() => {
    fetch(ORDER_ROUTE)
      .then((response) => response.json())
      .then((payload: string[]) => setOrders(payload));
  }, []);
  return <ul>{orders.map((order) => <li key={order}>{order}</li>)}</ul>;
}
