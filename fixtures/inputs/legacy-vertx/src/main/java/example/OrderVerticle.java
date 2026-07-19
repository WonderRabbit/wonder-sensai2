package example;

import io.vertx.core.AbstractVerticle;
import io.vertx.ext.web.Router;

public final class OrderVerticle extends AbstractVerticle {
  @Override
  public void start() {
    Router router = Router.router(vertx);
    router.get("/orders").handler(context -> {
      context.response()
          .putHeader("content-type", "application/json")
          .end("[]");
    });
    router.post("/orders").handler(context -> {
      vertx.eventBus().publish("order.created", context.body().asString());
      context.response().setStatusCode(202).end();
    });
  }
}
