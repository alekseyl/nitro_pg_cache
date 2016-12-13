# DB way
Shipment.scope
        .joins(purchase: :product)
        .select(["shipments.*","sum(purchases.items_count*products.gross_weight) as gross_weight"])
        .group("shipments.id")
